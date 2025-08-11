#!/bin/bash
# ========================================
# CARLO SSL RENEW SCRIPT
# ========================================
# Renova certificados SSL Let's Encrypt para sites Python
# Uso: ./carlo-ssl-renew.sh <domain> [--force] [--all]

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Função para log
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERRO]${NC} $1"
    exit 1
}

success() {
    echo -e "${GREEN}[SUCESSO]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

# Verificar argumentos
FORCE=false
RENEW_ALL=false
DOMAIN=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --all)
            RENEW_ALL=true
            shift
            ;;
        *)
            if [ -z "$DOMAIN" ]; then
                DOMAIN=$1
            else
                error "Argumento inválido: $1"
            fi
            shift
            ;;
    esac
done

# Função para renovar certificado de um domínio
renew_certificate() {
    local domain=$1
    local site_dir="/home/carlo/sites/$domain"
    
    log "Verificando certificado para $domain"
    
    # Verificar se o site existe
    if [ ! -d "$site_dir" ]; then
        warning "Site $domain não encontrado, pulando..."
        return 1
    fi
    
    # Verificar se tem certificado SSL
    if [ ! -d "/home/carlo/ssl/$domain/live" ]; then
        warning "Site $domain não tem certificado SSL, pulando..."
        return 1
    fi
    
    # Verificar se o certificado precisa ser renovado
    local cert_file="/home/carlo/ssl/$domain/live/cert.pem"
    if [ ! -f "$cert_file" ]; then
        warning "Certificado não encontrado para $domain, pulando..."
        return 1
    fi
    
    # Verificar data de expiração
    local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
    if [ -z "$expiry_date" ]; then
        warning "Não foi possível verificar expiração para $domain, pulando..."
        return 1
    fi
    
    # Converter para timestamp
    local expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null)
    local current_timestamp=$(date +%s)
    local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
    
    log "Certificado $domain expira em $days_until_expiry dias ($expiry_date)"
    
    # Renovar se expira em menos de 30 dias ou se forçado
    if [ "$days_until_expiry" -lt 30 ] || [ "$FORCE" = true ]; then
        log "Renovando certificado para $domain..."
        
        # Verificar se o site está rodando
        if ! sudo supervisorctl status "$domain" 2>/dev/null | grep -q "RUNNING"; then
            warning "Site $domain não está rodando, iniciando..."
            sudo supervisorctl start "$domain"
            sleep 3
        fi
        
        # Backup da configuração atual
        if [ -f "/home/carlo/nginx/sites-available/$domain" ]; then
            cp "/home/carlo/nginx/sites-available/$domain" "/home/carlo/nginx/sites-available/$domain.backup.$(date +%Y%m%d_%H%M%S)"
        fi
        
        # Obter porta do site
        local port=$(jq -r '.port // 5000' "$site_dir/status.json" 2>/dev/null || echo "5000")
        
        # Criar configuração Nginx temporária para renovação
        cat > "/home/carlo/nginx/sites-available/$domain" << EOF
server {
    listen 80;
    server_name $domain www.$domain;
    
    # Logs
    access_log $site_dir/logs/access.log;
    error_log $site_dir/logs/error.log;
    
    # Proxy para Python
    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Arquivos estáticos
    location /static/ {
        alias $site_dir/current/static/;
        expires 30d;
    }
}
EOF
        
        # Recarregar Nginx
        if sudo nginx -t; then
            sudo systemctl reload nginx
        else
            error "Erro na configuração Nginx para $domain"
            return 1
        fi
        
        # Renovar certificado
        local email=$(jq -r '.ssl_email // "admin@'$domain'"' "$site_dir/status.json" 2>/dev/null || echo "admin@$domain")
        
        local certbot_cmd="sudo certbot certonly --webroot \
            --webroot-path=$site_dir/public \
            --email $email \
            --agree-tos \
            --no-eff-email \
            --cert-name $domain \
            -d $domain \
            -d www.$domain"
        
        if [ "$FORCE" = true ]; then
            certbot_cmd="$certbot_cmd --force-renewal"
        fi
        
        if eval $certbot_cmd; then
            success "Certificado renovado para $domain"
            
            # Copiar certificados atualizados
            sudo cp -r "/etc/letsencrypt/live/$domain" "/home/carlo/ssl/$domain/"
            sudo cp -r "/etc/letsencrypt/archive/$domain" "/home/carlo/ssl/$domain/"
            sudo chown -R vito:vito "/home/carlo/ssl/$domain"
            
            # Restaurar configuração Nginx com SSL
            cat > "/home/carlo/nginx/sites-available/$domain" << EOF
# Configuração SSL para $domain
server {
    listen 80;
    server_name $domain www.$domain;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $domain www.$domain;
    
    # SSL Configuration
    ssl_certificate /home/carlo/ssl/$domain/live/fullchain.pem;
    ssl_certificate_key /home/carlo/ssl/$domain/live/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Logs
    access_log $site_dir/logs/access.log;
    error_log $site_dir/logs/error.log;
    
    # Proxy para Python
    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
    }
    
    # Arquivos estáticos
    location /static/ {
        alias $site_dir/current/static/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
EOF
            
            # Testar e recarregar Nginx
            if sudo nginx -t; then
                sudo systemctl reload nginx
                success "Nginx atualizado para $domain"
            else
                error "Erro na configuração Nginx para $domain"
                return 1
            fi
            
            # Atualizar status
            local new_expiry=$(openssl x509 -in "/home/carlo/ssl/$domain/live/cert.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
            cat > "$site_dir/status.json" << EOF
{
    "domain": "$domain",
    "port": $port,
    "framework": "$(jq -r '.framework // "flask"' "$site_dir/status.json" 2>/dev/null || echo "flask")",
    "python_version": "$(jq -r '.python_version // "3.12"' "$site_dir/status.json" 2>/dev/null || echo "3.12")",
    "status": "running",
    "ssl_enabled": true,
    "ssl_expires": "$new_expiry",
    "ssl_email": "$email",
    "created_at": "$(jq -r '.created_at // "'$(date -Iseconds)'"' "$site_dir/status.json" 2>/dev/null || echo "$(date -Iseconds)")",
    "ssl_renewed_at": "$(date -Iseconds)"
}
EOF
            
            return 0
        else
            error "Falha na renovação do certificado para $domain"
            return 1
        fi
    else
        log "Certificado $domain ainda é válido ($days_until_expiry dias restantes)"
        return 0
    fi
}

# Se --all foi especificado, renovar todos os sites
if [ "$RENEW_ALL" = true ]; then
    log "Renovando certificados para todos os sites..."
    
    renewed_count=0
    failed_count=0
    
    for site_dir in /home/carlo/sites/*/; do
        if [ -d "$site_dir" ]; then
            domain=$(basename "$site_dir")
            if renew_certificate "$domain"; then
                ((renewed_count++))
            else
                ((failed_count++))
            fi
        fi
    done
    
    echo ""
    echo "📋 Resumo da renovação:"
    echo "   ✅ Renovados: $renewed_count"
    echo "   ❌ Falharam: $failed_count"
    echo ""
    
    if [ $renewed_count -gt 0 ]; then
        success "Renovação concluída!"
    else
        warning "Nenhum certificado foi renovado"
    fi
    
    exit 0
fi

# Verificar se o domínio foi fornecido
if [ -z "$DOMAIN" ]; then
    error "Uso: $0 <domain> [--force]"
    echo "       $0 --all [--force]"
    echo ""
    echo "Exemplos:"
    echo "  $0 meusite.com              # Renovar certificado específico"
    echo "  $0 meusite.com --force      # Forçar renovação"
    echo "  $0 --all                    # Renovar todos os certificados"
    echo "  $0 --all --force            # Forçar renovação de todos"
    exit 1
fi

# Renovar certificado específico
if renew_certificate "$DOMAIN"; then
    echo ""
    echo "📋 Informações da renovação:"
    echo "   Domínio: $DOMAIN"
    echo "   Status: Renovado com sucesso"
    echo "   Nova expiração: $(openssl x509 -in /home/carlo/ssl/$DOMAIN/live/cert.pem -noout -enddate 2>/dev/null | cut -d= -f2 || echo "unknown")"
    echo ""
    echo "🔧 Comandos úteis:"
    echo "   ./carlo-ssl-status.sh $DOMAIN    # Verificar status SSL"
    echo "   ./carlo-nginx-edit.sh $DOMAIN    # Editar configuração Nginx"
    echo "   ./carlo-logs.sh $DOMAIN          # Ver logs"
else
    error "Falha na renovação do certificado para $DOMAIN"
    exit 1
fi 