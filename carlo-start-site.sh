#!/bin/bash
# ========================================
# CARLO START SITE SCRIPT
# ========================================
# Inicia um site Python gerenciado pelo Carlo
# Uso: ./carlo-start-site.sh <domain>

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

log "Iniciando site: $DOMAIN"

# Verificar se o supervisor está configurado
if [ ! -f "/etc/supervisor/conf.d/$DOMAIN.conf" ]; then
    error "Configuração do supervisor não encontrada para $DOMAIN"
    echo "Execute: ./carlo-create-site.sh $DOMAIN <port> para configurar o site"
    exit 1
fi

# Verificar se o virtual environment existe
if [ ! -d "$SITE_DIR/public/venv" ]; then
    warning "Virtual environment não encontrado, criando..."
    cd "$SITE_DIR/public"
    
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

# Verificar se as dependências estão instaladas
if [ -f "$SITE_DIR/public/requirements.txt" ]; then
    log "Verificando dependências..."
    cd "$SITE_DIR/public"
    source venv/bin/activate
    pip install -r requirements.txt --quiet
fi

# Verificar se a porta está livre
PORT=$(jq -r '.port // 5000' "$SITE_DIR/status.json" 2>/dev/null || echo "5000")
if netstat -tuln 2>/dev/null | grep -q ":$PORT "; then
    warning "Porta $PORT já está em uso"
    echo "Verificando se é o próprio site..."
    if ! sudo supervisorctl status "$DOMAIN" 2>/dev/null | grep -q "RUNNING"; then
        error "Porta $PORT está sendo usada por outro processo"
    fi
fi

# Iniciar o site via supervisor
log "Iniciando processo via supervisor..."
sudo supervisorctl start "$DOMAIN"

# Aguardar um pouco para o processo inicializar
sleep 2

# Verificar se iniciou corretamente
if sudo supervisorctl status "$DOMAIN" | grep -q "RUNNING"; then
    success "Site $DOMAIN iniciado com sucesso!"
    
    # Atualizar status.json
    cat > "$SITE_DIR/status.json" << EOF
{
    "domain": "$DOMAIN",
    "port": $PORT,
    "framework": "$(jq -r '.framework // "unknown"' "$SITE_DIR/status.json" 2>/dev/null || echo "unknown")",
    "python_version": "$(jq -r '.python_version // "3.12"' "$SITE_DIR/status.json" 2>/dev/null || echo "3.12")",
    "status": "running",
    "created_at": "$(jq -r '.created_at // "'$(date -Iseconds)'"' "$SITE_DIR/status.json" 2>/dev/null || echo "$(date -Iseconds)")",
    "last_started": "$(date -Iseconds)",
    "last_stopped": "$(jq -r '.last_stopped // null' "$SITE_DIR/status.json" 2>/dev/null || echo "null")"
}
EOF
    
    echo ""
    echo "📋 Informações do site:"
    echo "   Domínio: $DOMAIN"
    echo "   Porta: $PORT"
    echo "   Status: running"
    echo "   PID: $(sudo supervisorctl status $DOMAIN | awk '{print $4}' | cut -d',' -f1)"
    echo ""
    echo "🌐 URLs de acesso:"
    echo "   http://$DOMAIN (após configurar DNS)"
    echo "   http://localhost:$PORT (localmente)"
    echo ""
    echo "📝 Logs disponíveis em:"
    echo "   $SITE_DIR/logs/app.log"
    echo ""
    echo "🔧 Comandos úteis:"
    echo "   sudo supervisorctl stop $DOMAIN    # Parar site"
    echo "   sudo supervisorctl restart $DOMAIN # Reiniciar site"
    echo "   tail -f $SITE_DIR/logs/app.log    # Ver logs em tempo real"
    
else
    error "Falha ao iniciar site $DOMAIN"
    echo ""
    echo "🔍 Verificando logs de erro:"
    echo "   sudo supervisorctl status $DOMAIN"
    echo "   tail -n 20 $SITE_DIR/logs/app.log"
    echo ""
    echo "💡 Possíveis soluções:"
    echo "   1. Verificar se a porta $PORT está livre"
    echo "   2. Verificar se as dependências estão instaladas"
    echo "   3. Verificar se o arquivo app.py existe e está correto"
    exit 1
fi 