#!/bin/bash
# ========================================
# CARLO DELETE SITE SCRIPT
# ========================================
# Deleta um site Python gerenciado pelo Carlo
# Uso: ./carlo-delete-site.sh <domain> [--force] [--json]

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
JSON_OUTPUT=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        *)
            DOMAIN=$1
            shift
            ;;
    esac
done

if [ -z "$DOMAIN" ]; then
    error "Uso: $0 <domain> [--force] [--json]"
    echo "Exemplo: $0 meusite.com"
    echo "         $0 meusite.com --force  # Força a exclusão sem confirmação"
    echo "         $0 meusite.com --json   # Output em formato JSON"
    exit 1
fi

SITE_DIR="/home/carlo/sites/$DOMAIN"

# Verificar se o site existe
if [ ! -d "$SITE_DIR" ]; then
    if [ "$JSON_OUTPUT" = true ]; then
        echo "{\"success\":false,\"error\":\"Site $DOMAIN não encontrado\",\"domain\":\"$DOMAIN\"}"
    else
        error "Site $DOMAIN não encontrado"
        echo "Sites disponíveis:"
        ls -1 /home/carlo/sites/ 2>/dev/null || echo "  Nenhum site encontrado"
    fi
    exit 1
fi

# Se não for modo JSON e não for forçado, mostrar informações (apenas para uso manual)
if [ "$JSON_OUTPUT" != true ] && [ "$FORCE" != true ] && [ -t 0 ]; then
    echo -e "${YELLOW}⚠️  ATENÇÃO: Você está prestes a deletar o site $DOMAIN${NC}"
    echo ""
    echo "📋 Informações do site:"
    echo "   Domínio: $DOMAIN"
    echo "   Diretório: $SITE_DIR"
    echo "   Tamanho: $(du -sh "$SITE_DIR" 2>/dev/null | cut -f1 || echo 'desconhecido')"
    echo "   Status: $(sudo supervisorctl status $DOMAIN 2>/dev/null || echo 'não configurado')"
    echo ""

    # Verificar se há dados importantes
    if [ -d "$SITE_DIR/shared" ] && [ "$(ls -A "$SITE_DIR/shared" 2>/dev/null)" ]; then
        warning "Diretório 'shared' contém dados que serão perdidos!"
        echo "   Conteúdo: $(ls -la "$SITE_DIR/shared" | wc -l) arquivos"
    fi

    if [ -d "$SITE_DIR/ssl" ] && [ "$(ls -A "$SITE_DIR/ssl" 2>/dev/null)" ]; then
        warning "Certificados SSL serão perdidos!"
    fi

    # Confirmação do usuário apenas em modo interativo
    echo -e "${RED}❌ Esta ação é IRREVERSÍVEL!${NC}"
    echo ""
    read -p "Digite 'DELETE $DOMAIN' para confirmar: " confirmation
    
    if [ "$confirmation" != "DELETE $DOMAIN" ]; then
        echo -e "${YELLOW}Operação cancelada pelo usuário${NC}"
        exit 0
    fi
fi

log "Deletando site: $DOMAIN"

# Parar o site se estiver rodando
if sudo supervisorctl status "$DOMAIN" 2>/dev/null | grep -q "RUNNING"; then
    log "Parando site antes da exclusão..."
    sudo supervisorctl stop "$DOMAIN"
    sleep 2
fi

# Remover configuração do supervisor
if [ -f "/etc/supervisor/conf.d/$DOMAIN.conf" ]; then
    log "Removendo configuração do supervisor..."
    sudo rm -f "/etc/supervisor/conf.d/$DOMAIN.conf"
    sudo supervisorctl reread
    sudo supervisorctl update
fi

# Remover configuração do Nginx
NGINX_CONF="/home/carlo/nginx/sites-available/$DOMAIN"
if [ -f "$NGINX_CONF" ]; then
    log "Removendo configuração do Nginx..."
    sudo rm -f "$NGINX_CONF"
    
    # Remover link simbólico se existir
    if [ -L "/etc/nginx/sites-enabled/$DOMAIN" ]; then
        sudo rm -f "/etc/nginx/sites-enabled/$DOMAIN"
    fi
    
    # Recarregar Nginx
    if sudo nginx -t; then
        sudo systemctl reload nginx
    fi
fi

# Fazer backup antes de deletar (opcional)
BACKUP_DIR="/home/carlo/backups/deleted_sites"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/${DOMAIN}_$(date +%Y%m%d_%H%M%S).tar.gz"

log "Criando backup antes da exclusão..."
tar -czf "$BACKUP_FILE" -C "$SITE_DIR" . 2>/dev/null || warning "Falha ao criar backup"

# Deletar diretório do site
log "Removendo diretório do site..."
sudo rm -rf "$SITE_DIR"

# Verificar se foi deletado
if [ ! -d "$SITE_DIR" ]; then
    if [ "$JSON_OUTPUT" = true ]; then
        echo "{\"success\":true,\"message\":\"Site $DOMAIN deletado com sucesso\",\"domain\":\"$DOMAIN\",\"backup_file\":\"$BACKUP_FILE\",\"timestamp\":\"$(date -Iseconds)\"}"
    else
        success "Site $DOMAIN deletado com sucesso!"
        
        echo ""
        echo "📋 Resumo da operação:"
        echo "   ✅ Site parado"
        echo "   ✅ Configuração do supervisor removida"
        echo "   ✅ Configuração do Nginx removida"
        echo "   ✅ Diretório do site deletado"
        if [ -f "$BACKUP_FILE" ]; then
            echo "   ✅ Backup criado: $BACKUP_FILE"
        fi
        echo ""
        echo "💾 Backup disponível em:"
        echo "   $BACKUP_FILE"
        echo ""
        echo "🔧 Para restaurar (se necessário):"
        echo "   mkdir -p /home/carlo/sites/$DOMAIN"
        echo "   tar -xzf $BACKUP_FILE -C /home/carlo/sites/$DOMAIN"
        echo "   ./carlo-create-site.sh $DOMAIN <port>"
    fi
    
else
    if [ "$JSON_OUTPUT" = true ]; then
        echo "{\"success\":false,\"error\":\"Falha ao deletar site $DOMAIN\",\"domain\":\"$DOMAIN\"}"
    else
        error "Falha ao deletar site $DOMAIN"
        echo ""
        echo "🔍 Verificando o que pode ter falhado:"
        echo "   ls -la $SITE_DIR"
        echo "   sudo supervisorctl status $DOMAIN"
        echo "   ls -la /etc/supervisor/conf.d/ | grep $DOMAIN"
    fi
    exit 1
fi 