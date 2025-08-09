#!/bin/bash
# ========================================
# CARLO SSL SETUP SCRIPT
# ========================================
# Gera e instala certificados SSL Let's Encrypt para sites Python
# Uso: ./carlo-ssl-setup.sh <domain> [--force] [--email email]

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
EMAIL=""
DOMAIN=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --email)
            EMAIL=$2
            shift 2
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

# Verificar se o domínio foi fornecido
if [ -z "$DOMAIN" ]; then
    error "Uso: $0 <domain> [--force] [--email email]"
    echo "Exemplo: $0 meusite.com"
    echo "         $0 meusite.com --force"
    echo "         $0 meusite.com --email admin@meusite.com"
    exit 1
fi

SITE_DIR="/home/carlo/sites/$DOMAIN"

# Verificar se o site existe
if [ ! -d "$SITE_DIR" ]; then
    error "Site $DOMAIN não encontrado"
    echo "Execute: ./carlo-create-site.sh $DOMAIN <port> para criar o site"
    exit 1
fi

# Verificar se certbot está instalado
if ! command -v certbot &> /dev/null; then
    warning "Certbot não encontrado, instalando..."
    sudo apt update
    sudo apt install -y certbot python3-certbot-nginx
fi

log "Configurando SSL para $DOMAIN"

# Verificar se o site está rodando
if ! sudo supervisorctl status "$DOMAIN" 2>/dev/null | grep -q "RUNNING"; then
    warning "Site $DOMAIN não está rodando"
    echo "Iniciando site para validação SSL..."
    sudo supervisorctl start "$DOMAIN"
    sleep 3
fi

# Verificar se o DNS está apontando para o servidor
log "Verificando DNS..."
SERVER_IP=$(curl -s ifconfig.me)
DOMAIN_IP=$(dig +short $DOMAIN | head -1)

if [ -z "$DOMAIN_IP" ]; then
    error "Não foi possível resolver o DNS para $DOMAIN"
    echo "Verifique se o domínio está configurado corretamente"
    exit 1
fi

if [ "$DOMAIN_IP" != "$SERVER_IP" ]; then
    warning "DNS não está apontando para este servidor"
    echo "   Domínio $DOMAIN resolve para: $DOMAIN_IP"
    echo "   Este servidor: $SERVER_IP"
    echo ""
    echo "O certificado pode falhar se o DNS não estiver correto"
    if [ "$FORCE" != true ]; then
        read -p "Continuar mesmo assim? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

# Criar diretório SSL se não existir
mkdir -p "/home/carlo/ssl/$DOMAIN"

# Verificar se já existe certificado
if [ -d "/home/carlo/ssl/$DOMAIN/live" ] && [ "$FORCE" != true ]; then
    warning "Certificado SSL já existe para $DOMAIN"
    echo "Use --force para renovar"
    exit 0
fi

# Configurar email para Let's Encrypt
if [ -z "$EMAIL" ]; then
    EMAIL="admin@$DOMAIN"
fi

# Criar configuração Nginx para validação
log "Configurando Nginx para validação SSL..."

# Backup da configuração atual
if [ -f "/home/carlo/nginx/sites-available/$DOMAIN" ]; then
    cp "/home/carlo/nginx/sites-available/$DOMAIN" "/home/carlo/nginx/sites-available/$DOMAIN.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Obter porta do site
PORT=$(jq -r '.port // 5000' "$SITE_DIR/status.json" 2>/dev/null || echo "5000")

# Criar configuração Nginx temporária para validação
cat > "/home/carlo/nginx/sites-available/$DOMAIN" << EOF
server {
    listen 80;
    server_name $DOMAIN;
    
    # Logs
    access_log $SITE_DIR/logs/access.log;
    error_log $SITE_DIR/logs/error.log;
    
    # Let's Encrypt validation
    location /.well-known/acme-challenge/ {
        root /home/carlo/webroot;
    }
    
    # Proxy para Python
    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Arquivos estáticos
    location /static/ {
        alias $SITE_DIR/public/static/;
        expires 30d;
    }
}
EOF

# Recarregar Nginx
if sudo nginx -t; then
    sudo systemctl reload nginx
    success "Nginx recarregado"
else
    error "Erro na configuração Nginx"
fi

# Gerar certificado SSL
log "Gerando certificado SSL..."

# Comando certbot
CERTBOT_CMD="sudo certbot certonly --webroot \
    --webroot-path=/home/carlo/webroot \
    --email $EMAIL \
    --agree-tos \
    --no-eff-email \
    --cert-name $DOMAIN \
    -d $DOMAIN"

if [ "$FORCE" = true ]; then
    CERTBOT_CMD="$CERTBOT_CMD --force-renewal"
fi

# Executar certbot
if eval $CERTBOT_CMD; then
    success "Certificado SSL gerado com sucesso!"
    
    # Copiar certificados para diretório Carlo
    log "Copiando certificados..."
    
    # Criar estrutura de diretórios
    sudo mkdir -p "/home/carlo/ssl/$DOMAIN/live"
    sudo mkdir -p "/home/carlo/ssl/$DOMAIN/archive"
    
    # Copiar certificados para live
    sudo cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "/home/carlo/ssl/$DOMAIN/live/"
    sudo cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "/home/carlo/ssl/$DOMAIN/live/"
    sudo cp "/etc/letsencrypt/live/$DOMAIN/cert.pem" "/home/carlo/ssl/$DOMAIN/live/"
    sudo cp "/etc/letsencrypt/live/$DOMAIN/chain.pem" "/home/carlo/ssl/$DOMAIN/live/"
    
    # Copiar certificados para archive (se existir)
    if [ -d "/etc/letsencrypt/archive/$DOMAIN" ] && [ "$(ls -A "/etc/letsencrypt/archive/$DOMAIN" 2>/dev/null)" ]; then
        sudo cp -r "/etc/letsencrypt/archive/$DOMAIN/"* "/home/carlo/ssl/$DOMAIN/archive/"
    else
        log "Diretório archive não encontrado ou vazio, pulando..."
    fi
    
    # Ajustar permissões
    sudo chown -R vito:vito "/home/carlo/ssl/$DOMAIN"
    sudo chmod 644 "/home/carlo/ssl/$DOMAIN/live/"*.pem
    sudo chmod 600 "/home/carlo/ssl/$DOMAIN/live/privkey.pem"
    
    # Criar configuração Nginx com SSL
    log "Configurando Nginx com SSL..."
    cat > "/home/carlo/nginx/sites-available/$DOMAIN" << EOF
# Configuração SSL para $DOMAIN
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;
    
    # SSL Configuration
    ssl_certificate /home/carlo/ssl/$DOMAIN/live/fullchain.pem;
    ssl_certificate_key /home/carlo/ssl/$DOMAIN/live/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Logs
    access_log $SITE_DIR/logs/access.log;
    error_log $SITE_DIR/logs/error.log;
    
    # Proxy para Python
    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
    }
    
    # Arquivos estáticos
    location /static/ {
        alias $SITE_DIR/public/static/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
EOF
    
    # Testar e recarregar Nginx
    if sudo nginx -t; then
        sudo systemctl reload nginx
        success "Nginx configurado com SSL"
    else
        error "Erro na configuração Nginx com SSL"
        # Restaurar backup
        if [ -f "/home/carlo/nginx/sites-available/$DOMAIN.backup" ]; then
            cp "/home/carlo/nginx/sites-available/$DOMAIN.backup" "/home/carlo/nginx/sites-available/$DOMAIN"
            sudo nginx -t && sudo systemctl reload nginx
        fi
        exit 1
    fi
    
    # Atualizar status do site
    cat > "$SITE_DIR/status.json" << EOF
{
    "domain": "$DOMAIN",
    "port": $PORT,
    "framework": "$(jq -r '.framework // "flask"' "$SITE_DIR/status.json" 2>/dev/null || echo "flask")",
    "python_version": "$(jq -r '.python_version // "3.12"' "$SITE_DIR/status.json" 2>/dev/null || echo "3.12")",
    "status": "running",
    "ssl_enabled": true,
    "ssl_expires": "$(openssl x509 -in /home/carlo/ssl/$DOMAIN/live/cert.pem -noout -enddate 2>/dev/null | cut -d= -f2 || echo "unknown")",
    "created_at": "$(jq -r '.created_at // "'$(date -Iseconds)'"' "$SITE_DIR/status.json" 2>/dev/null || echo "$(date -Iseconds)")",
    "ssl_installed_at": "$(date -Iseconds)"
}
EOF
    
    echo ""
    echo "📋 Informações do SSL:"
    echo "   Domínio: $DOMAIN"
    echo "   Email: $EMAIL"
    echo "   Certificado: /home/carlo/ssl/$DOMAIN/live/"
    echo "   Expira em: $(openssl x509 -in /home/carlo/ssl/$DOMAIN/live/cert.pem -noout -enddate 2>/dev/null | cut -d= -f2 || echo "unknown")"
    echo ""
    echo "🌐 URLs de acesso:"
    echo "   https://$DOMAIN"
    echo ""
    echo "🔧 Comandos úteis:"
    echo "   ./carlo-ssl-renew.sh $DOMAIN    # Renovar certificado"
    echo "   ./carlo-nginx-edit.sh $DOMAIN   # Editar configuração Nginx"
    echo "   ./carlo-logs.sh $DOMAIN         # Ver logs"
    
else
    error "Falha na geração do certificado SSL"
    echo ""
    echo "🔍 Possíveis causas:"
    echo "   1. DNS não está apontando para este servidor"
    echo "   2. Porta 80 não está acessível"
    echo "   3. Domínio não é válido"
    echo ""
    echo "💡 Soluções:"
    echo "   1. Verifique o DNS: dig $DOMAIN"
    echo "   2. Teste acesso: curl -I http://$DOMAIN"
    echo "   3. Verifique logs: sudo tail -f /var/log/letsencrypt/letsencrypt.log"
    exit 1
fi 