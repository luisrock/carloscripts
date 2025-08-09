#!/bin/bash
# ========================================
# CARLO DEPLOY UNIFIED SCRIPT
# ========================================
# Deploy unificado para manual e automático via GitHub
# Uso: ./carlo-deploy-unified.sh <domain> [branch] [--force]

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
    echo "Branch: $BRANCH"
    echo "================================"
    echo ""
    
    log "Iniciando deploy para $DOMAIN (branch: $BRANCH)"
    
    # Verificar se o site está configurado para GitHub
    if [ ! -f "$SITE_DIR/config/github.conf" ]; then
        error "Site $DOMAIN não está configurado para GitHub"
        echo "Execute: ./carlo-github-setup.sh $DOMAIN <repo> para configurar"
        exit 1
    fi

    # Carregar configuração GitHub
    source "$SITE_DIR/config/github.conf"
    
    log "Repositório GitHub: $GITHUB_REPO"
    
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
    RELEASE_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    RELEASE_DIR="$SITE_DIR/releases/$RELEASE_TIMESTAMP"
    mkdir -p "$RELEASE_DIR"

    log "Criando nova release: $RELEASE_TIMESTAMP"

    # Determinar URL do repositório (público via HTTPS ou privado via SSH)
    REPO_URL=""
    if git ls-remote "https://github.com/$GITHUB_REPO.git" > /dev/null 2>&1; then
        log "Repositório acessível via HTTPS (público)"
        REPO_URL="https://github.com/$GITHUB_REPO.git"
    elif git ls-remote "git@github.com:$GITHUB_REPO.git" > /dev/null 2>&1; then
        log "Repositório acessível via SSH (privado)"
        REPO_URL="git@github.com:$GITHUB_REPO.git"
    else
        error "Repositório GitHub não encontrado ou não acessível: $GITHUB_REPO"
        echo "Verifique se o repositório existe e se você tem acesso via SSH (para repositórios privados)"
        exit 1
    fi

    # Clonar/atualizar código
    if [ -d "$SITE_DIR/repo" ]; then
        log "Atualizando repositório existente..."
        cd "$SITE_DIR/repo"
        git fetch origin
        git reset --hard origin/$BRANCH
        git clean -fd
    else
        log "Clonando repositório..."
        git clone -b $BRANCH "$REPO_URL" "$SITE_DIR/repo"
        cd "$SITE_DIR/repo"
    fi

    # Copiar código para nova release
    log "Copiando código para nova release..."
    cp -r "$SITE_DIR/repo"/* "$RELEASE_DIR/"

    # Vincular artefatos compartilhados (.env e instance) de forma estável entre releases
    SHARED_DIR="$SITE_DIR/shared"
    mkdir -p "$SHARED_DIR/instance"

    # Preferir .env canônico em shared; se não existir, usar o .env gerenciado pela UI em public
    CANON_ENV=""
    if [ -f "$SHARED_DIR/.env" ]; then
        CANON_ENV="$SHARED_DIR/.env"
    elif [ -f "$SITE_DIR/public/.env" ]; then
        CANON_ENV="$SITE_DIR/public/.env"
    fi

    # Symlinks dentro da release atual
    ln -sfn "$SHARED_DIR/instance" "$RELEASE_DIR/instance"
    if [ -n "$CANON_ENV" ]; then
        ln -sfn "$CANON_ENV" "$RELEASE_DIR/.env"
    fi

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
        pip install gunicorn
    else
        warning "requirements.txt não encontrado, criando básico..."
        cat > "$RELEASE_DIR/requirements.txt" << EOF
# Requirements gerados automaticamente
Flask==3.0.0
Werkzeug==3.0.1
gunicorn==21.2.0
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
        
        pip install --upgrade pip
        pip install -r requirements.txt
        pip install gunicorn
    fi

    # Copiar arquivos compartilhados
    if [ -d "$SITE_DIR/shared" ]; then
        log "Copiando arquivos compartilhados..."
        cp -r "$SITE_DIR/shared"/* "$RELEASE_DIR/" 2>/dev/null || true
    fi

    # Copiar configuração Gunicorn se existir
    if [ -f "$SITE_DIR/gunicorn.conf" ]; then
        log "Copiando configuração Gunicorn..."
        cp "$SITE_DIR/gunicorn.conf" "$RELEASE_DIR/"
    else
        log "Criando configuração Gunicorn padrão..."
        cat > "$RELEASE_DIR/gunicorn.conf" << EOF
bind = "127.0.0.1:$PORT"
workers = 2
worker_class = "sync"
worker_connections = 1000
timeout = 30
keepalive = 2
max_requests = 1000
max_requests_jitter = 50
preload_app = True
EOF
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

    # Executar deploy script customizado (se existir) antes de configurar supervisor
    PORT=$(jq -r '.port // 5000' "$SITE_DIR/status.json" 2>/dev/null || echo "5000")
    CANDIDATES=(
      "$RELEASE_DIR/deploy.sh"
      "$SITE_DIR/deploy.sh"
    )
    for CAND in "${CANDIDATES[@]}"; do
        if [ -s "$CAND" ]; then
            log "Executando script de deploy: $CAND"
            chmod +x "$CAND"
            (
              cd "$(dirname "$CAND")"
              DOMAIN="$DOMAIN" \
              SITE_DIR="$SITE_DIR" \
              RELEASE_DIR="$RELEASE_DIR" \
              CURRENT_DIR="$SITE_DIR/current" \
              SHARED_DIR="$SITE_DIR/shared" \
              BRANCH="$BRANCH" \
              PORT="$PORT" \
              TIMESTAMP="$RELEASE_TIMESTAMP" \
              GITHUB_REPO="$GITHUB_REPO" \
              VENV="$RELEASE_DIR/venv" \
              PYTHON_BIN="$RELEASE_DIR/venv/bin/python" \
              ./"$(basename "$CAND")"
            ) || {
              error "Falha ao executar script de deploy ($CAND)"
              exit 1
            }
            break
        fi
    done

    # Atualizar supervisor para nova release
    log "Atualizando configuração do supervisor..."
    # PORT já pode ter sido definido acima; garantir fallback
    PORT=${PORT:-$(jq -r '.port // 5000' "$SITE_DIR/status.json" 2>/dev/null || echo "5000")}

    sudo tee "/etc/supervisor/conf.d/$DOMAIN.conf" > /dev/null << EOF
[program:$DOMAIN]
command=$RELEASE_DIR/venv/bin/gunicorn -c $RELEASE_DIR/gunicorn.conf app:app
directory=$RELEASE_DIR
user=vito
autostart=false
autorestart=true
redirect_stderr=true
stdout_logfile=$SITE_DIR/logs/app.log
environment=PORT=$PORT,GITHUB_BRANCH="$BRANCH",DEPLOY_TIMESTAMP="$RELEASE_TIMESTAMP"
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
    "deploy_timestamp": "$RELEASE_TIMESTAMP"
}
EOF
        
        echo ""
        echo "📋 Informações do deploy:"
        echo "   Domínio: $DOMAIN"
        echo "   Repositório: $GITHUB_REPO"
        echo "   Branch: $BRANCH"
        echo "   Release: $RELEASE_TIMESTAMP"
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
        echo "   ./carlo-deploy-unified.sh $DOMAIN $BRANCH    # Deploy manual"
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

    success "Deploy unificado concluído com sucesso!"
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