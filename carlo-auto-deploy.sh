#!/bin/bash
# ========================================
# CARLO AUTO DEPLOY SCRIPT
# ========================================
# Executa deploy automático quando webhook GitHub é recebido
# Uso: ./carlo-auto-deploy.sh {domain} {branch} {commit_sha}
# Exemplo: ./carlo-auto-deploy.sh meusite.com main abc123

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
if [ $# -lt 3 ]; then
    error "Uso: $0 {domain} {branch} {commit_sha}"
    exit 1
fi

DOMAIN=$1
BRANCH=$2
COMMIT_SHA=$3

# Carregar configuração do site
SITE_DIR="/home/carlo/sites/$DOMAIN"
STATUS_FILE="$SITE_DIR/status.json"

if [ ! -f "$STATUS_FILE" ]; then
    error "Site $DOMAIN não encontrado"
    exit 1
fi

# Verificar se auto-deploy está habilitado
AUTO_DEPLOY_ENABLED=$(jq -r '.auto_deploy_enabled // false' "$STATUS_FILE")
if [ "$AUTO_DEPLOY_ENABLED" != "true" ]; then
    warning "Auto-deploy não está habilitado para $DOMAIN"
    exit 0
fi

# Extrair informações do status.json
GITHUB_REPO=$(jq -r '.github_repo // empty' "$STATUS_FILE")
GITHUB_BRANCH=$(jq -r '.github_branch // "main"' "$STATUS_FILE")

if [ -z "$GITHUB_REPO" ]; then
    error "Site $DOMAIN não tem repositório GitHub configurado"
    exit 1
fi

# Verificar se é o branch correto
if [ "$BRANCH" != "$GITHUB_BRANCH" ]; then
    log "Push para branch $BRANCH (ignorando, configurado para $GITHUB_BRANCH)"
    exit 0
fi

log "Iniciando auto-deploy para $DOMAIN"
log "Repositório: $GITHUB_REPO"
log "Branch: $BRANCH"
log "Commit: $COMMIT_SHA"

# Gerar timestamp único para o deploy
DEPLOY_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$SITE_DIR/deploy-logs/auto-deploy_${DEPLOY_TIMESTAMP}.log"

# Criar diretório de logs se não existir
mkdir -p "$SITE_DIR/deploy-logs"

# Função para log com timestamp
log_with_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Iniciar log do deploy
log_with_timestamp "=== AUTO-DEPLOY INICIADO ==="
log_with_timestamp "Domínio: $DOMAIN"
log_with_timestamp "Repositório: $GITHUB_REPO"
log_with_timestamp "Branch: $BRANCH"
log_with_timestamp "Commit: $COMMIT_SHA"
log_with_timestamp "Timestamp: $DEPLOY_TIMESTAMP"

# Verificar se o site está rodando
SITE_STATUS=$(jq -r '.status // "unknown"' "$STATUS_FILE")
if [ "$SITE_STATUS" != "running" ]; then
    log_with_timestamp "AVISO: Site não está rodando (status: $SITE_STATUS)"
fi

# Executar deploy usando o script existente
log_with_timestamp "Executando deploy..."
cd "$SITE_DIR"

# Usar sempre o script de deploy unificado (igual ao deploy manual)
log_with_timestamp "Usando script de deploy unificado"
DEPLOY_SCRIPT="/home/carlo/scripts/carlo-deploy-unified.sh"

# Executar deploy
if bash "$DEPLOY_SCRIPT" "$DOMAIN" "$BRANCH" "$COMMIT_SHA" >> "$LOG_FILE" 2>&1; then
    DEPLOY_SUCCESS=true
    log_with_timestamp "=== AUTO-DEPLOY CONCLUÍDO COM SUCESSO ==="
    success "Auto-deploy concluído com sucesso para $DOMAIN"
else
    DEPLOY_SUCCESS=false
    log_with_timestamp "=== AUTO-DEPLOY FALHOU ==="
    error "Auto-deploy falhou para $DOMAIN"
fi

# Atualizar status.json com informações do deploy
jq --arg timestamp "$DEPLOY_TIMESTAMP" \
   --arg commit "$COMMIT_SHA" \
   --arg success "$DEPLOY_SUCCESS" \
   --arg log_file "$LOG_FILE" \
   '.last_auto_deploy = {
     timestamp: $timestamp,
     commit: $commit,
     success: ($success == "true"),
     log_file: $log_file
   }' "$STATUS_FILE" > "$STATUS_FILE.tmp" && mv "$STATUS_FILE.tmp" "$STATUS_FILE"

# Retornar sucesso ou falha
if [ "$DEPLOY_SUCCESS" = "true" ]; then
    exit 0
else
    exit 1
fi 