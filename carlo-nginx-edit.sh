#!/bin/bash
# ========================================
# CARLO NGINX EDIT SCRIPT
# ========================================
# Lê, edita e salva configurações Nginx para sites Python
# Uso: ./carlo-nginx-edit.sh <domain> [--read] [--write] [--validate]

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
ACTION=""
DOMAIN=""
CONFIG_CONTENT=""
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --read)
            ACTION="read"
            shift
            ;;
        --write)
            ACTION="write"
            shift
            ;;
        --validate)
            ACTION="validate"
            shift
            ;;
        --content)
            CONFIG_CONTENT="$2"
            shift 2
            ;;
        --json)
            JSON_OUTPUT=true
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

# Verificar se o domínio foi fornecido
if [ -z "$DOMAIN" ]; then
    error "Uso: $0 <domain> [--read|--write|--validate] [--content 'config']"
    echo ""
    echo "Exemplos:"
    echo "  $0 meusite.com --read                    # Ler configuração atual"
    echo "  $0 meusite.com --write --content '...'   # Salvar nova configuração"
    echo "  $0 meusite.com --validate --content '...' # Validar configuração"
    echo ""
    echo "Para uso via interface web:"
    echo "  --read: Retorna JSON com configuração atual"
    echo "  --write: Salva configuração e retorna status"
    echo "  --validate: Valida configuração sem salvar"
    exit 1
fi

SITE_DIR="/home/carlo/sites/$DOMAIN"
NGINX_CONF="/home/carlo/nginx/sites-available/$DOMAIN"

# Verificar se o site existe
if [ ! -d "$SITE_DIR" ]; then
    error "Site $DOMAIN não encontrado"
    echo "Execute: ./carlo-create-site.sh $DOMAIN <port> para criar o site"
    exit 1
fi

# Função para ler configuração atual
read_config() {
    if [ -f "$NGINX_CONF" ]; then
        if [ "$JSON_OUTPUT" = true ]; then
            # Retornar em formato JSON para interface web
            echo "{\"domain\":\"$DOMAIN\",\"config\":$(cat "$NGINX_CONF" | jq -Rs .),\"exists\":true,\"timestamp\":\"$(date -Iseconds)\"}"
        else
            # Retornar texto simples
            echo "=== CONFIGURAÇÃO NGINX PARA $DOMAIN ==="
            echo ""
            cat "$NGINX_CONF"
            echo ""
            echo "=== FIM DA CONFIGURAÇÃO ==="
        fi
    else
        if [ "$JSON_OUTPUT" = true ]; then
            echo "{\"domain\":\"$DOMAIN\",\"config\":\"\",\"exists\":false,\"timestamp\":\"$(date -Iseconds)\"}"
        else
            warning "Configuração Nginx não encontrada para $DOMAIN"
            echo "Execute: ./carlo-create-site.sh $DOMAIN <port> para criar a configuração"
        fi
    fi
}

# Função para validar configuração
validate_config() {
    local temp_file="/tmp/nginx_validate_$DOMAIN.conf"
    
    # Criar arquivo de configuração temporário com contexto http
    cat > "$temp_file" << EOF
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    $CONFIG_CONTENT
}
EOF
    
    # Testar configuração
    if sudo nginx -t -c "$temp_file" 2>/dev/null; then
        success "Configuração Nginx válida"
        rm -f "$temp_file"
        return 0
    else
        error "Configuração Nginx inválida"
        echo ""
        echo "🔍 Erros encontrados:"
        sudo nginx -t -c "$temp_file" 2>&1 | grep -E "(error|failed)" || echo "Erro desconhecido"
        rm -f "$temp_file"
        return 1
    fi
}

# Função para salvar configuração
save_config() {
    # Validar configuração primeiro
    if ! validate_config; then
        exit 1
    fi
    
    # Backup da configuração atual
    if [ -f "$NGINX_CONF" ]; then
        local backup_file="$NGINX_CONF.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$NGINX_CONF" "$backup_file"
        log "Backup criado: $backup_file"
    fi
    
    # Salvar nova configuração
    log "Salvando configuração Nginx..."
    echo "$CONFIG_CONTENT" > "$NGINX_CONF"
    
    # Testar configuração completa
    if sudo nginx -t; then
        # Recarregar Nginx
        sudo systemctl reload nginx
        success "Configuração Nginx salva e aplicada"
        
        # Atualizar status do site
        local port=$(jq -r '.port // 5000' "$SITE_DIR/status.json" 2>/dev/null || echo "5000")
        cat > "$SITE_DIR/status.json" << EOF
{
    "domain": "$DOMAIN",
    "port": $port,
    "framework": "$(jq -r '.framework // "flask"' "$SITE_DIR/status.json" 2>/dev/null || echo "flask")",
    "python_version": "$(jq -r '.python_version // "3.12"' "$SITE_DIR/status.json" 2>/dev/null || echo "3.12")",
    "status": "running",
    "nginx_updated_at": "$(date -Iseconds)",
    "created_at": "$(jq -r '.created_at // "'$(date -Iseconds)'"' "$SITE_DIR/status.json" 2>/dev/null || echo "$(date -Iseconds)")"
}
EOF
        
        if [ "$JSON_OUTPUT" = true ]; then
            echo "{\"success\":true,\"message\":\"Configuração salva com sucesso\",\"domain\":\"$DOMAIN\",\"timestamp\":\"$(date -Iseconds)\"}"
        else
            echo ""
            echo "📋 Informações:"
            echo "   Domínio: $DOMAIN"
            echo "   Status: Configuração aplicada"
            echo "   Backup: $backup_file"
            echo ""
            echo "🔧 Comandos úteis:"
            echo "   ./carlo-nginx-edit.sh $DOMAIN --read    # Ler configuração"
            echo "   ./carlo-logs.sh $DOMAIN --type nginx    # Ver logs Nginx"
            echo "   ./carlo-ssl-status.sh $DOMAIN          # Verificar SSL"
        fi
    else
        error "Erro na configuração Nginx"
        echo ""
        echo "🔍 Erros encontrados:"
        sudo nginx -t 2>&1 | grep -E "(error|failed)" || echo "Erro desconhecido"
        echo ""
        echo "💡 Restaurando backup..."
        if [ -f "$backup_file" ]; then
            cp "$backup_file" "$NGINX_CONF"
            sudo nginx -t && sudo systemctl reload nginx
            success "Backup restaurado"
        fi
        exit 1
    fi
}

# Executar ação solicitada
case $ACTION in
    "read")
        read_config
        ;;
    "write")
        if [ -z "$CONFIG_CONTENT" ]; then
            error "Conteúdo da configuração não fornecido"
            echo "Use --content 'configuração'"
            exit 1
        fi
        save_config
        ;;
    "validate")
        if [ -z "$CONFIG_CONTENT" ]; then
            error "Conteúdo da configuração não fornecido"
            echo "Use --content 'configuração'"
            exit 1
        fi
        if validate_config; then
            if [ "$JSON_OUTPUT" = true ]; then
                echo "{\"valid\":true,\"message\":\"Configuração válida\",\"domain\":\"$DOMAIN\"}"
            else
                success "Configuração válida"
            fi
        else
            if [ "$JSON_OUTPUT" = true ]; then
                echo "{\"valid\":false,\"message\":\"Configuração inválida\",\"domain\":\"$DOMAIN\"}"
            else
                error "Configuração inválida"
            fi
            exit 1
        fi
        ;;
    "")
        # Modo interativo
        echo -e "${CYAN}🔧 EDITOR DE CONFIGURAÇÃO NGINX - $DOMAIN${NC}"
        echo "=========================================="
        echo ""
        
        # Mostrar configuração atual
        echo "📄 Configuração atual:"
        echo "------------------------"
        if [ -f "$NGINX_CONF" ]; then
            cat "$NGINX_CONF"
        else
            echo "Nenhuma configuração encontrada"
        fi
        echo ""
        
        # Perguntar se quer editar
        read -p "Deseja editar a configuração? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Criar arquivo temporário para edição
            local temp_file="/tmp/nginx_edit_$DOMAIN.conf"
            if [ -f "$NGINX_CONF" ]; then
                cp "$NGINX_CONF" "$temp_file"
            else
                # Criar configuração padrão
                local port=$(jq -r '.port // 5000' "$SITE_DIR/status.json" 2>/dev/null || echo "5000")
                cat > "$temp_file" << EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    
    # Logs
    access_log $SITE_DIR/logs/access.log;
    error_log $SITE_DIR/logs/error.log;
    
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
        alias $SITE_DIR/public/static/;
        expires 30d;
    }
}
EOF
            fi
            
            # Abrir editor
            if command -v nano &> /dev/null; then
                nano "$temp_file"
            elif command -v vim &> /dev/null; then
                vim "$temp_file"
            else
                error "Nenhum editor encontrado (nano ou vim)"
                exit 1
            fi
            
            # Perguntar se quer salvar
            read -p "Salvar alterações? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                CONFIG_CONTENT=$(cat "$temp_file")
                save_config
            else
                echo "Alterações descartadas"
            fi
            
            # Limpar arquivo temporário
            rm -f "$temp_file"
        else
            echo "Operação cancelada"
        fi
        ;;
    *)
        error "Ação inválida: $ACTION"
        echo "Ações válidas: --read, --write, --validate"
        exit 1
        ;;
esac 