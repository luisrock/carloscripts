#!/bin/bash
# ========================================
# CARLO GITHUB WEBHOOK SCRIPT
# ========================================
# Gerencia webhooks do GitHub para auto-deploy
# Uso: ./carlo-github-webhook.sh {domain} {action} [options]
# Exemplo: ./carlo-github-webhook.sh meusite.com create
# Exemplo: ./carlo-github-webhook.sh meusite.com remove

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para log
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Função para erro
error() {
    echo -e "${RED}[ERRO]${NC} $1"
}

# Função para sucesso
success() {
    echo -e "${GREEN}[SUCESSO]${NC} $1"
}

# Função para aviso
warning() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

# Verificar parâmetros
if [ $# -lt 2 ]; then
    error "Uso: $0 {domain} {action} [options]"
    echo "Ações disponíveis:"
    echo "  create - Criar webhook para auto-deploy"
    echo "  remove - Remover webhook"
    echo "  status - Verificar status do webhook"
    echo "  list   - Listar webhooks do repositório"
    exit 1
fi

DOMAIN=$1
ACTION=$2

# Carregar configuração do site
SITE_DIR="/home/carlo/sites/$DOMAIN"
STATUS_FILE="$SITE_DIR/status.json"

if [ ! -f "$STATUS_FILE" ]; then
    error "Site $DOMAIN não encontrado"
    exit 1
fi

# Extrair informações do status.json
GITHUB_REPO=$(jq -r '.github_repo // empty' "$STATUS_FILE")
GITHUB_BRANCH=$(jq -r '.github_branch // "main"' "$STATUS_FILE")

if [ -z "$GITHUB_REPO" ]; then
    error "Site $DOMAIN não tem repositório GitHub configurado"
    exit 1
fi

# Gerar secret único para o webhook
WEBHOOK_SECRET=$(openssl rand -hex 32)
WEBHOOK_URL="https://python.maurolopes.com.br/api/sites/webhook"

# Verificar se GitHub CLI está autenticado
if ! gh auth status >/dev/null 2>&1; then
    error "GitHub CLI não está autenticado. Execute: gh auth login"
    exit 1
fi

case $ACTION in
    create)
        log "Criando webhook para auto-deploy: $DOMAIN"
        log "Repositório: $GITHUB_REPO"
        log "Branch: $GITHUB_BRANCH"
        
        # Verificar se webhook já existe
        EXISTING_WEBHOOK=$(gh api repos/$GITHUB_REPO/hooks --jq '.[] | select(.config.url == "'$WEBHOOK_URL'") | .id')
        
        if [ -n "$EXISTING_WEBHOOK" ]; then
            warning "Webhook já existe (ID: $EXISTING_WEBHOOK). Removendo..."
            gh api repos/$GITHUB_REPO/hooks/$EXISTING_WEBHOOK --method DELETE
        fi
        
        # Criar novo webhook
        # Criar arquivo JSON temporário para o webhook
        WEBHOOK_CONFIG=$(mktemp)
        cat > "$WEBHOOK_CONFIG" << EOF
{
  "name": "web",
  "active": true,
  "events": ["push"],
  "config": {
    "url": "$WEBHOOK_URL",
    "content_type": "json",
    "secret": "$WEBHOOK_SECRET"
  }
}
EOF
        
        WEBHOOK_RESPONSE=$(gh api repos/$GITHUB_REPO/hooks \
            --method POST \
            --input "$WEBHOOK_CONFIG")
        
        # Limpar arquivo temporário
        rm -f "$WEBHOOK_CONFIG"
        
        WEBHOOK_ID=$(echo "$WEBHOOK_RESPONSE" | jq -r '.id')
        
        if [ "$WEBHOOK_ID" != "null" ] && [ "$WEBHOOK_ID" != "" ]; then
            # Salvar informações do webhook no status.json
            jq --arg secret "$WEBHOOK_SECRET" \
               --arg webhook_id "$WEBHOOK_ID" \
               --arg webhook_url "$WEBHOOK_URL" \
               '.webhook_secret = $secret | .webhook_id = $webhook_id | .webhook_url = $webhook_url | .auto_deploy_enabled = true' \
               "$STATUS_FILE" > "$STATUS_FILE.tmp" && mv "$STATUS_FILE.tmp" "$STATUS_FILE"
            
            success "Webhook criado com sucesso!"
            echo "📋 Informações do webhook:"
            echo "   ID: $WEBHOOK_ID"
            echo "   URL: $WEBHOOK_URL"
            echo "   Secret: $WEBHOOK_SECRET"
            echo "   Repositório: $GITHUB_REPO"
            echo "   Branch: $GITHUB_BRANCH"
            echo "   Eventos: push"
            echo ""
            echo "🚀 Auto-deploy ativado para $DOMAIN"
            echo "   Qualquer push para $GITHUB_BRANCH irá triggerar deploy automático"
        else
            error "Falha ao criar webhook"
            exit 1
        fi
        ;;
        
    remove)
        log "Removendo webhook para auto-deploy: $DOMAIN"
        
        # Buscar webhook existente
        WEBHOOK_ID=$(jq -r '.webhook_id // empty' "$STATUS_FILE")
        
        if [ -n "$WEBHOOK_ID" ] && [ "$WEBHOOK_ID" != "null" ]; then
            # Remover webhook do GitHub
            gh api repos/$GITHUB_REPO/hooks/$WEBHOOK_ID --method DELETE
            
            # Limpar informações do webhook no status.json
            jq 'del(.webhook_secret, .webhook_id, .webhook_url) | .auto_deploy_enabled = false' \
               "$STATUS_FILE" > "$STATUS_FILE.tmp" && mv "$STATUS_FILE.tmp" "$STATUS_FILE"
            
            success "Webhook removido com sucesso!"
            echo "🚫 Auto-deploy desativado para $DOMAIN"
        else
            warning "Nenhum webhook encontrado para $DOMAIN"
        fi
        ;;
        
    status)
        log "Verificando status do webhook: $DOMAIN"
        
        WEBHOOK_ID=$(jq -r '.webhook_id // empty' "$STATUS_FILE")
        AUTO_DEPLOY_ENABLED=$(jq -r '.auto_deploy_enabled // false' "$STATUS_FILE")
        
        if [ -n "$WEBHOOK_ID" ] && [ "$WEBHOOK_ID" != "null" ]; then
            # Verificar se webhook ainda existe no GitHub
            if gh api repos/$GITHUB_REPO/hooks/$WEBHOOK_ID >/dev/null 2>&1; then
                success "Webhook ativo"
                echo "📋 Status:"
                echo "   ID: $WEBHOOK_ID"
                echo "   Repositório: $GITHUB_REPO"
                echo "   Branch: $GITHUB_BRANCH"
                echo "   Auto-deploy: $([ "$AUTO_DEPLOY_ENABLED" = "true" ] && echo "Ativado" || echo "Desativado")"
            else
                warning "Webhook não encontrado no GitHub (pode ter sido removido manualmente)"
                echo "📋 Status local:"
                echo "   Auto-deploy: $([ "$AUTO_DEPLOY_ENABLED" = "true" ] && echo "Ativado" || echo "Desativado")"
            fi
        else
            echo "📋 Status: Auto-deploy não configurado"
        fi
        ;;
        
    list)
        log "Listando webhooks do repositório: $GITHUB_REPO"
        
        WEBHOOKS=$(gh api repos/$GITHUB_REPO/hooks)
        
        if [ "$(echo "$WEBHOOKS" | jq 'length')" -gt 0 ]; then
            echo "$WEBHOOKS" | jq -r '.[] | "ID: \(.id), Nome: \(.name), URL: \(.config.url), Ativo: \(.active)"'
        else
            echo "Nenhum webhook encontrado"
        fi
        ;;
        
    *)
        error "Ação inválida: $ACTION"
        echo "Ações disponíveis: create, remove, status, list"
        exit 1
        ;;
esac 