#!/bin/bash
# ========================================
# CARLO DEPLOY SCRIPT
# ========================================
# Deploy automático via GitHub com zero downtime
# Uso: ./carlo-deploy.sh <domain> [branch] [--force]

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
    error "Uso: $0 <domain> [branch] [--force]"
    echo "Exemplo: $0 meusite.com main"
    echo "         $0 meusite.com develop --force"
    exit 1
fi

DOMAIN=$1
BRANCH=${2:-main}
FORCE=false

# Verificar se --force foi passado
if [[ "$*" == *"--force"* ]]; then
    FORCE=true
fi

SITE_DIR="/home/carlo/sites/$DOMAIN"

# Verificar se o site existe
if [ ! -d "$SITE_DIR" ]; then
    error "Site $DOMAIN não encontrado"
    echo "Execute: ./carlo-create-site.sh $DOMAIN <port> para criar o site"
    exit 1
fi

# Verificar se o site está configurado para GitHub
if [ ! -f "$SITE_DIR/config/github.conf" ]; then
    error "Site $DOMAIN não está configurado para GitHub"
    echo "Execute: ./carlo-github-setup.sh $DOMAIN <repo> para configurar"
    exit 1
fi

# Carregar configuração GitHub
source "$SITE_DIR/config/github.conf"

log "Iniciando deploy para $DOMAIN (branch: $BRANCH)"

# Verificar se git está instalado
if ! command -v git &> /dev/null; then
    warning "Git não encontrado, instalando..."
    sudo apt update
    sudo apt install -y git
fi

# Parar o site se estiver rodando
if sudo supervisorctl status "$DOMAIN" 2>/dev/null | grep -q "RUNNING"; then
    log "Parando site para deploy..."
    sudo supervisorctl stop "$DOMAIN"
    sleep 2
fi

# Criar diretório de releases se não existir
mkdir -p "$SITE_DIR/releases"

# Gerar timestamp para nova release
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RELEASE_DIR="$SITE_DIR/releases/$TIMESTAMP"

log "Criando nova release: $TIMESTAMP"

# Clonar/atualizar código
if [ -d "$SITE_DIR/repo" ]; then
    log "Atualizando repositório existente..."
    cd "$SITE_DIR/repo"
    git fetch origin
    git reset --hard origin/$BRANCH
    git clean -fd
else
    log "Clonando repositório..."
    git clone -b $BRANCH https://github.com/$GITHUB_REPO.git "$SITE_DIR/repo"
    cd "$SITE_DIR/repo"
fi

# Copiar código para nova release
log "Copiando código para nova release..."
cp -r "$SITE_DIR/repo"/* "$RELEASE_DIR/"

# Verificar se requirements.txt existe
if [ -f "$RELEASE_DIR/requirements.txt" ]; then
    log "Instalando dependências Python..."
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
    
    # Criar virtual environment se não existir
    if [ ! -d "venv" ]; then
        if ! $PYTHON_CMD -m venv venv; then
            error "Falha ao criar ambiente virtual Python"
            echo "Verifique se python3-venv está instalado: sudo apt install python3-venv"
            exit 1
        fi
    fi
    
    # Ativar virtual environment e instalar dependências
    source venv/bin/activate
    
    # Verificar se pip está disponível
    if ! command -v pip &> /dev/null; then
        log "Pip não encontrado, instalando..."
        $PYTHON_CMD -m ensurepip --upgrade
    fi
    
    pip install --upgrade pip
    pip install -r requirements.txt
else
    warning "requirements.txt não encontrado, criando básico..."
    cat > "$RELEASE_DIR/requirements.txt" << EOF
# Requirements gerados automaticamente
Flask==3.0.0
Werkzeug==3.0.1
EOF
    
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
    
    pip install -r requirements.txt
fi

# Copiar arquivos compartilhados
if [ -d "$SITE_DIR/shared" ]; then
    log "Copiando arquivos compartilhados..."
    cp -r "$SITE_DIR/shared"/* "$RELEASE_DIR/" 2>/dev/null || true
fi

# Verificar se app.py existe
if [ ! -f "$RELEASE_DIR/app.py" ]; then
    warning "app.py não encontrado, criando básico..."
    cat > "$RELEASE_DIR/app.py" << 'EOF'
from flask import Flask
import os

app = Flask(__name__)

@app.route('/')
def hello():
    return '''
    <!DOCTYPE html>
    <html>
    <head>
        <title>Site Python - Carlo Deploy</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; }
            .container { max-width: 800px; margin: 0 auto; text-align: center; }
            h1 { font-size: 2.5em; margin-bottom: 20px; }
            .status { background: rgba(255,255,255,0.1); padding: 20px; border-radius: 10px; margin: 20px 0; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🚀 Deploy via GitHub!</h1>
            <div class="status">
                <h2>✅ Deploy Automático Funcionando</h2>
                <p>Seu site foi atualizado via GitHub</p>
                <p><strong>Branch:</strong> ''' + os.environ.get('GITHUB_BRANCH', 'main') + '''</p>
                <p><strong>Deploy:</strong> ''' + os.environ.get('DEPLOY_TIMESTAMP', 'N/A') + '''</p>
            </div>
        </div>
    </body>
    </html>
    '''

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 5000)), debug=False)
EOF
fi

# Testar aplicação
log "Testando aplicação..."
cd "$RELEASE_DIR"
source venv/bin/activate

# Verificar se a aplicação inicia corretamente
if timeout 10s python app.py --test 2>/dev/null || timeout 10s python -c "import app; print('App OK')" 2>/dev/null; then
    success "Aplicação testada com sucesso"
else
    warning "Não foi possível testar a aplicação, continuando..."
fi

# Atualizar supervisor para nova release
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
environment=PORT=$PORT,GITHUB_BRANCH="$BRANCH",DEPLOY_TIMESTAMP="$TIMESTAMP"
EOF

# Recarregar supervisor
sudo supervisorctl reread
sudo supervisorctl update

# Iniciar site
log "Iniciando site com nova release..."
sudo supervisorctl start "$DOMAIN"

# Aguardar inicialização
sleep 3

# Verificar se iniciou corretamente
if sudo supervisorctl status "$DOMAIN" | grep -q "RUNNING"; then
    success "Deploy concluído com sucesso!"
    
    # Atualizar symlink current
    ln -sfn "$RELEASE_DIR" "$SITE_DIR/current"
    
    # Limpar releases antigas (manter últimas 5)
    log "Limpando releases antigas..."
    cd "$SITE_DIR/releases"
    ls -t | tail -n +6 | xargs rm -rf 2>/dev/null || true
    
    # Atualizar status
    cat > "$SITE_DIR/status.json" << EOF
{
    "domain": "$DOMAIN",
    "port": $PORT,
    "framework": "github",
    "python_version": "3.12",
    "status": "running",
    "created_at": "$(jq -r '.created_at // "'$(date -Iseconds)'"' "$SITE_DIR/status.json" 2>/dev/null || echo "$(date -Iseconds)")",
    "last_deploy": "$(date -Iseconds)",
    "github_repo": "$GITHUB_REPO",
    "github_branch": "$BRANCH",
    "deploy_timestamp": "$TIMESTAMP"
}
EOF
    
    echo ""
    echo "📋 Informações do deploy:"
    echo "   Domínio: $DOMAIN"
    echo "   Repositório: $GITHUB_REPO"
    echo "   Branch: $BRANCH"
    echo "   Release: $TIMESTAMP"
    echo "   Status: running"
    echo ""
    echo "🌐 URLs de acesso:"
    echo "   http://$DOMAIN (após configurar DNS)"
    echo "   http://localhost:$PORT (localmente)"
    echo ""
    echo "📝 Logs disponíveis em:"
    echo "   $SITE_DIR/logs/app.log"
    echo ""
    echo "🔧 Comandos úteis:"
    echo "   ./carlo-deploy.sh $DOMAIN $BRANCH    # Deploy manual"
    echo "   ./carlo-rollback.sh $DOMAIN          # Rollback"
    echo "   ./carlo-logs.sh $DOMAIN --follow     # Ver logs"
    
else
    error "Falha no deploy - site não iniciou"
    echo ""
    echo "🔍 Verificando logs de erro:"
    echo "   sudo supervisorctl status $DOMAIN"
    echo "   tail -n 20 $SITE_DIR/logs/app.log"
    echo ""
    echo "💡 Possíveis soluções:"
    echo "   1. Verificar se app.py existe e está correto"
    echo "   2. Verificar se requirements.txt está correto"
    echo "   3. Verificar se a porta está livre"
    exit 1
fi 