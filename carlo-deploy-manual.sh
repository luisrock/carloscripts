#!/bin/bash
# ========================================
# CARLO DEPLOY MANUAL SCRIPT
# ========================================
# Deploy manual sem dependência GitHub
# Uso: ./carlo-deploy-manual.sh <domain> [--force]

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
    error "Uso: $0 <domain> [--force]"
    echo "Exemplo: $0 meusite.com"
    echo "         $0 meusite.com --force"
    exit 1
fi

DOMAIN=$1
FORCE=false

# Verificar se --force foi passado
if [[ "$*" == *"--force"* ]]; then
    FORCE=true
fi

# Configurações
SITE_DIR="/home/carlo/sites/$DOMAIN"
PUBLIC_DIR="$SITE_DIR/public"
LOGS_DIR="$SITE_DIR/deploy-logs"

# Verificar se o site existe
if [ ! -d "$SITE_DIR" ]; then
    error "Site $DOMAIN não encontrado"
    exit 1
fi

# Criar diretório de logs se não existir
mkdir -p "$LOGS_DIR"

# Gerar timestamp para o log
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOGS_DIR/${TIMESTAMP}.log"

# Iniciar log
{
    echo "=== LOG DE DEPLOY: $DOMAIN ==="
    echo "Timestamp: $TIMESTAMP"
    echo "Data/Hora: $(date)"
    echo "================================"
    echo ""
    
    log "Iniciando deploy manual para $DOMAIN"
    
    # Resolver e executar script de deploy, se existir (ordem: release -> site). Caso contrário, criar default.
    RELEASE_DIR="$SITE_DIR/current"
    CANDIDATES=(
      "$RELEASE_DIR/deploy.sh"
      "$SITE_DIR/deploy.sh"
    )
    FOUND=""
    for CAND in "${CANDIDATES[@]}"; do
        if [ -f "$CAND" ]; then
            FOUND="$CAND"; break
        fi
    done

    if [ -n "$FOUND" ]; then
        log "Executando script de deploy: $FOUND"
        chmod +x "$FOUND"
        (
          cd "$(dirname "$FOUND")"
          DOMAIN="$DOMAIN" \
          SITE_DIR="$SITE_DIR" \
          RELEASE_DIR="$RELEASE_DIR" \
          CURRENT_DIR="$SITE_DIR/current" \
          SHARED_DIR="$SITE_DIR/shared" \
          PORT="$(jq -r '.port // 5000' "$SITE_DIR/status.json" 2>/dev/null || echo "5000")" \
          TIMESTAMP="$(date +%Y%m%d_%H%M%S)" \
          VENV="$RELEASE_DIR/venv" \
          PYTHON_BIN="$RELEASE_DIR/venv/bin/python" \
          bash -lc "./$(basename \"$FOUND\")"
        ) || error "Falha ao executar deploy.sh"
        success "Deploy script executado com sucesso!"
    else
        log "Nenhum script de deploy encontrado. Criando padrão em $SITE_DIR/deploy.sh..."
        
        # Criar script de deploy padrão
        cat > "$SITE_DIR/deploy.sh" << 'SCRIPT_EOF'
#!/bin/bash
# Deploy script para $DOMAIN
# Este script será executado quando o site for deployado

set -e

echo "Iniciando deploy para $DOMAIN..."

# Navegar para o diretório do site
cd /home/carlo/sites/$DOMAIN/public

# Se existe requirements.txt, instalar dependências
if [ -f "requirements.txt" ]; then
    echo "Instalando dependências Python..."
    # Usar o virtual environment se existir
    if [ -d "venv" ]; then
        echo "Usando virtual environment existente..."
        source venv/bin/activate
        pip install -r requirements.txt
    else
        echo "Criando novo virtual environment..."
        python3 -m venv venv
        source venv/bin/activate
        pip install -r requirements.txt
    fi
fi

# Se existe package.json, instalar dependências Node.js
if [ -f "package.json" ]; then
    echo "Instalando dependências Node.js..."
    npm install
fi

# Restart da aplicação
echo "Reiniciando aplicação..."
sudo supervisorctl restart $DOMAIN

echo "Deploy concluído com sucesso!"
SCRIPT_EOF

        chmod +x "$SITE_DIR/deploy.sh"
        success "Script de deploy padrão criado!"
    fi

    # Verificar se a aplicação está rodando
    if sudo supervisorctl status $DOMAIN | grep -q RUNNING; then
        success "Aplicação $DOMAIN está rodando"
    else
        warning "Aplicação $DOMAIN não está rodando"
        log "Iniciando aplicação..."
        sudo supervisorctl start $DOMAIN
    fi

    success "Deploy manual concluído com sucesso!"
    echo ""
    echo "Duração: $(($(date +%s) - $(date -d "$(date)" +%s)))s"
    
} 2>&1 | tee "$LOG_FILE"

# Manter apenas os últimos 20 logs
cd "$LOGS_DIR"
ls -t *.log 2>/dev/null | tail -n +21 | xargs rm -f 2>/dev/null || true

# Retornar o status baseado no log
if grep -q "SUCESSO.*Deploy.*concluído" "$LOG_FILE"; then
    exit 0
else
    exit 1
fi 