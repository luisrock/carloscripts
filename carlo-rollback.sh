#!/bin/bash
# ========================================
# CARLO ROLLBACK SCRIPT
# ========================================
# Rollback rápido para versão anterior
# Uso: ./carlo-rollback.sh <domain> [release_number]

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
if [ $# -lt 1 ]; then
    error "Uso: $0 <domain> [release_number]"
    echo "Exemplo: $0 meusite.com"
    echo "         $0 meusite.com 20250727_143022"
    exit 1
fi

DOMAIN=$1
RELEASE_NUMBER=$2

SITE_DIR="/home/carlo/sites/$DOMAIN"

# Verificar se o site existe
if [ ! -d "$SITE_DIR" ]; then
    error "Site $DOMAIN não encontrado"
    exit 1
fi

# Verificar se o site tem releases
if [ ! -d "$SITE_DIR/releases" ]; then
    error "Site $DOMAIN não tem releases"
    echo "Execute: ./carlo-deploy.sh $DOMAIN para criar releases"
    exit 1
fi

log "Iniciando rollback para $DOMAIN"

# Listar releases disponíveis
RELEASES=($(ls -t "$SITE_DIR/releases" 2>/dev/null))
if [ ${#RELEASES[@]} -eq 0 ]; then
    error "Nenhuma release encontrada"
    exit 1
fi

# Se não especificou release, usar a segunda mais recente (rollback automático)
if [ -z "$RELEASE_NUMBER" ]; then
    if [ ${#RELEASES[@]} -lt 2 ]; then
        error "Apenas uma release disponível, não é possível fazer rollback"
        echo "Releases disponíveis:"
        for release in "${RELEASES[@]}"; do
            echo "   $release"
        done
        exit 1
    fi
    
    RELEASE_NUMBER=${RELEASES[1]}
    log "Rollback automático para: $RELEASE_NUMBER"
else
    # Verificar se a release especificada existe
    if [ ! -d "$SITE_DIR/releases/$RELEASE_NUMBER" ]; then
        error "Release $RELEASE_NUMBER não encontrada"
        echo "Releases disponíveis:"
        for release in "${RELEASES[@]}"; do
            echo "   $release"
        done
        exit 1
    fi
fi

RELEASE_DIR="$SITE_DIR/releases/$RELEASE_NUMBER"

log "Fazendo rollback para release: $RELEASE_NUMBER"

# Parar o site se estiver rodando
if sudo supervisorctl status "$DOMAIN" 2>/dev/null | grep -q "RUNNING"; then
    log "Parando site para rollback..."
    sudo supervisorctl stop "$DOMAIN"
    sleep 2
fi

# Verificar se a release tem a estrutura necessária
if [ ! -f "$RELEASE_DIR/app.py" ]; then
    error "Release $RELEASE_NUMBER não tem app.py"
    exit 1
fi

# Verificar se virtual environment existe
if [ ! -d "$RELEASE_DIR/venv" ]; then
    warning "Virtual environment não encontrado, criando..."
    cd "$RELEASE_DIR"
    
    # Verificar e encontrar o Python correto
    PYTHON_CMD=""
    if command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
    elif command -v python &> /dev/null; then
        PYTHON_CMD="python"
    elif [ -f "/usr/bin/python3" ]; then
        PYTHON_CMD="/usr/bin/python3"
    elif [ -f "/usr/bin/python" ]; then
        PYTHON_CMD="/usr/bin/python"
    else
        error "Python não encontrado. Instale Python 3: sudo apt install python3 python3-venv"
    fi
    
    if ! $PYTHON_CMD -m venv venv; then
        error "Falha ao criar ambiente virtual Python"
        echo "Verifique se python3-venv está instalado: sudo apt install python3-venv"
        exit 1
    fi
    
    source venv/bin/activate
    
    # Verificar se pip está disponível
    if ! command -v pip &> /dev/null; then
        log "Pip não encontrado, instalando..."
        $PYTHON_CMD -m ensurepip --upgrade
    fi
    
    pip install --upgrade pip
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt
    fi
fi

# Atualizar supervisor para a release de rollback
log "Atualizando configuração do supervisor..."
PORT=$(jq -r '.port // 5000' "$SITE_DIR/status.json" 2>/dev/null || echo "5000")

sudo tee "/etc/supervisor/conf.d/$DOMAIN.conf" > /dev/null << EOF
[program:$DOMAIN]
command=$RELEASE_DIR/venv/bin/python $RELEASE_DIR/app.py
directory=$RELEASE_DIR
user=vito
autostart=false
autorestart=true
redirect_stderr=true
stdout_logfile=$SITE_DIR/logs/app.log
environment=PORT=$PORT,ROLLBACK_RELEASE="$RELEASE_NUMBER",ROLLBACK_TIMESTAMP="$(date -Iseconds)"
EOF

# Recarregar supervisor
sudo supervisorctl reread
sudo supervisorctl update

# Iniciar site com a release de rollback
log "Iniciando site com release de rollback..."
sudo supervisorctl start "$DOMAIN"

# Aguardar inicialização
sleep 3

# Verificar se iniciou corretamente
if sudo supervisorctl status "$DOMAIN" | grep -q "RUNNING"; then
    success "Rollback concluído com sucesso!"
    
    # Atualizar symlink current
    ln -sfn "$RELEASE_DIR" "$SITE_DIR/current"
    
    # Atualizar status
    cat > "$SITE_DIR/status.json" << EOF
{
    "domain": "$DOMAIN",
    "port": $PORT,
    "framework": "github",
    "python_version": "3.12",
    "status": "running",
    "created_at": "$(jq -r '.created_at // "'$(date -Iseconds)'"' "$SITE_DIR/status.json" 2>/dev/null || echo "$(date -Iseconds)")",
    "last_rollback": "$(date -Iseconds)",
    "rollback_release": "$RELEASE_NUMBER",
    "github_repo": "$(jq -r '.github_repo // "unknown"' "$SITE_DIR/status.json" 2>/dev/null || echo "unknown")",
    "github_branch": "$(jq -r '.github_branch // "unknown"' "$SITE_DIR/status.json" 2>/dev/null || echo "unknown")"
}
EOF
    
    echo ""
    echo "📋 Informações do rollback:"
    echo "   Domínio: $DOMAIN"
    echo "   Release: $RELEASE_NUMBER"
    echo "   Status: running"
    echo "   Timestamp: $(date -Iseconds)"
    echo ""
    echo "🌐 URLs de acesso:"
    echo "   http://$DOMAIN (após configurar DNS)"
    echo "   http://localhost:$PORT (localmente)"
    echo ""
    echo "📝 Logs disponíveis em:"
    echo "   $SITE_DIR/logs/app.log"
    echo ""
    echo "🔧 Comandos úteis:"
    echo "   ./carlo-deploy.sh $DOMAIN main    # Deploy novo"
    echo "   ./carlo-logs.sh $DOMAIN --follow  # Ver logs"
    echo "   ./carlo-stats.sh                  # Ver estatísticas"
    echo ""
    echo "📋 Releases disponíveis:"
    for release in "${RELEASES[@]}"; do
        if [ "$release" = "$RELEASE_NUMBER" ]; then
            echo "   ✅ $release (atual)"
        else
            echo "   📦 $release"
        fi
    done
    
else
    error "Falha no rollback - site não iniciou"
    echo ""
    echo "🔍 Verificando logs de erro:"
    echo "   sudo supervisorctl status $DOMAIN"
    echo "   tail -n 20 $SITE_DIR/logs/app.log"
    echo ""
    echo "💡 Possíveis soluções:"
    echo "   1. Tentar rollback para outra release"
    echo "   2. Verificar se a release tem app.py válido"
    echo "   3. Verificar se as dependências estão instaladas"
    exit 1
fi 