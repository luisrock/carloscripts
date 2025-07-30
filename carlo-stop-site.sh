#!/bin/bash
# ========================================
# CARLO STOP SITE SCRIPT
# ========================================
# Para um site Python gerenciado pelo Carlo
# Uso: ./carlo-stop-site.sh <domain>

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
if [ $# -ne 1 ]; then
    error "Uso: $0 <domain>"
    echo "Exemplo: $0 meusite.com"
    exit 1
fi

DOMAIN=$1
SITE_DIR="/home/carlo/sites/$DOMAIN"

# Verificar se o site existe
if [ ! -d "$SITE_DIR" ]; then
    error "Site $DOMAIN não encontrado"
    echo "Sites disponíveis:"
    ls -1 /home/carlo/sites/ 2>/dev/null || echo "  Nenhum site encontrado"
    exit 1
fi

log "Parando site: $DOMAIN"

# Verificar se o supervisor está configurado
if [ ! -f "/etc/supervisor/conf.d/$DOMAIN.conf" ]; then
    error "Configuração do supervisor não encontrada para $DOMAIN"
    echo "Execute: ./carlo-create-site.sh $DOMAIN <port> para configurar o site"
    exit 1
fi

# Verificar se o site está rodando
if ! sudo supervisorctl status "$DOMAIN" 2>/dev/null | grep -q "RUNNING"; then
    warning "Site $DOMAIN não está rodando"
    echo "Status atual: $(sudo supervisorctl status $DOMAIN 2>/dev/null || echo 'não configurado')"
    exit 0
fi

# Parar o site via supervisor
log "Parando processo via supervisor..."
sudo supervisorctl stop "$DOMAIN"

# Aguardar um pouco para o processo parar
sleep 2

# Verificar se parou corretamente
if sudo supervisorctl status "$DOMAIN" | grep -q "STOPPED"; then
    success "Site $DOMAIN parado com sucesso!"
    
    # Atualizar status.json
    PORT=$(jq -r '.port // 5000' "$SITE_DIR/status.json" 2>/dev/null || echo "5000")
    cat > "$SITE_DIR/status.json" << EOF
{
    "domain": "$DOMAIN",
    "port": $PORT,
    "framework": "$(jq -r '.framework // "unknown"' "$SITE_DIR/status.json" 2>/dev/null || echo "unknown")",
    "python_version": "$(jq -r '.python_version // "3.12"' "$SITE_DIR/status.json" 2>/dev/null || echo "3.12")",
    "status": "stopped",
    "created_at": "$(jq -r '.created_at // "'$(date -Iseconds)'"' "$SITE_DIR/status.json" 2>/dev/null || echo "$(date -Iseconds)")",
    "last_started": "$(jq -r '.last_started // null' "$SITE_DIR/status.json" 2>/dev/null || echo "null")",
    "last_stopped": "$(date -Iseconds)"
}
EOF
    
    echo ""
    echo "📋 Informações do site:"
    echo "   Domínio: $DOMAIN"
    echo "   Porta: $PORT"
    echo "   Status: stopped"
    echo ""
    echo "🔧 Comandos úteis:"
    echo "   sudo supervisorctl start $DOMAIN   # Iniciar site"
    echo "   sudo supervisorctl restart $DOMAIN # Reiniciar site"
    echo "   tail -f $SITE_DIR/logs/app.log    # Ver logs"
    
else
    error "Falha ao parar site $DOMAIN"
    echo ""
    echo "🔍 Verificando status:"
    echo "   sudo supervisorctl status $DOMAIN"
    echo ""
    echo "💡 Possíveis soluções:"
    echo "   1. Tentar parar forçadamente: sudo supervisorctl stop $DOMAIN"
    echo "   2. Verificar se há processos órfãos: ps aux | grep $DOMAIN"
    echo "   3. Matar processo manualmente se necessário"
    exit 1
fi 