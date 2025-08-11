#!/bin/bash
# ========================================
# CARLO CREATE SITE SCRIPT
# ========================================
# Cria um novo site Python/Flask no sistema Carlo
# Uso: ./carlo-create-site.sh <domain> [python_version] [framework] [--github repo] [--branch branch]
# Exemplo: ./carlo-create-site.sh meusite.com 3.12 flask
# Exemplo: ./carlo-create-site.sh meusite.com 3.12 flask --github usuario/repositorio

set -e  # Para em caso de erro

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

# Função para gerar porta baseada no domínio
generate_port() {
    local domain=$1
    # Gerar hash do domínio e converter para número
    local hash=$(echo "$domain" | md5sum | cut -c1-8)
    local port_base=$((0x$hash % 9000))  # 0-8999
    local port=$((port_base + 1000))     # 1000-9999
    
    # Verificar se a porta está em uso e tentar a próxima
    local attempts=0
    while netstat -tuln | grep -q ":$port " && [ $attempts -lt 10 ]; do
        port=$((port + 1))
        attempts=$((attempts + 1))
        # Se passar de 9999, voltar para 1000
        if [ $port -gt 9999 ]; then
            port=1000
        fi
    done
    
    echo $port
}

# Verificar argumentos
if [ $# -lt 1 ]; then
    error "Uso: $0 <domain> [python_version] [framework] [--github repo] [--branch branch]"
    echo "Exemplo: $0 meusite.com 3.12 flask"
    echo "         $0 meusite.com 3.12 flask --github usuario/repositorio"
    echo "         $0 meusite.com 3.12 flask --github usuario/repositorio --branch develop"
    exit 1
fi

DOMAIN=$1
PYTHON_VERSION=${2:-3.12}
FRAMEWORK=${3:-flask}
GITHUB_REPO=""
GITHUB_BRANCH="main"

# Verificar se --github foi passado
if [[ "$*" == *"--github"* ]]; then
    for ((i=1; i<=$#; i++)); do
        if [ "${!i}" = "--github" ] && [ $((i+1)) -le $# ]; then
            next_i=$((i+1))
            GITHUB_REPO="${!next_i}"
            break
        fi
    done
fi

# Verificar se --branch foi passado
if [[ "$*" == *"--branch"* ]]; then
    for ((i=1; i<=$#; i++)); do
        if [ "${!i}" = "--branch" ] && [ $((i+1)) -le $# ]; then
            next_i=$((i+1))
            GITHUB_BRANCH="${!next_i}"
            break
        fi
    done
fi

# Validar domínio
if [[ ! $DOMAIN =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    error "Domínio inválido: $DOMAIN"
fi

# Gerar porta automaticamente
PORT=$(generate_port "$DOMAIN")
log "Porta gerada automaticamente: $PORT"

# Verificar se porta já está em uso (dupla verificação)
if netstat -tuln | grep -q ":$PORT "; then
    error "Porta $PORT já está em uso (tentativa de regeneração falhou)"
fi

# Verificar se domínio já existe
if [ -d "/home/carlo/sites/$DOMAIN" ]; then
    error "Site $DOMAIN já existe"
fi

# Validar GitHub repositório e branch se fornecidos
if [ -n "$GITHUB_REPO" ]; then
    log "Validando repositório GitHub: $GITHUB_REPO"
    
    # Verificar se git está instalado
    if ! command -v git &> /dev/null; then
        error "Git não está instalado. Execute: sudo apt install git"
    fi
    
    # Verificar se o repositório existe e é acessível
    # Tentar primeiro HTTPS (para repos públicos)
    if git ls-remote "https://github.com/$GITHUB_REPO.git" > /dev/null 2>&1; then
        log "Repositório acessível via HTTPS (público)"
        REPO_URL="https://github.com/$GITHUB_REPO.git"
    # Se falhar com HTTPS, tentar SSH (para repos privados)
    elif git ls-remote "git@github.com:$GITHUB_REPO.git" > /dev/null 2>&1; then
        log "Repositório acessível via SSH (privado)"
        REPO_URL="git@github.com:$GITHUB_REPO.git"
    else
        error "Repositório GitHub não encontrado ou não acessível: $GITHUB_REPO"
        echo ""
        echo "🔍 Verifique:"
        echo "   1. Se o repositório existe: https://github.com/$GITHUB_REPO"
        echo "   2. Se é público ou você tem acesso via SSH"
        echo "   3. Se o nome está correto (usuario/repositorio)"
        echo "   4. Se a chave SSH está configurada para repos privados"
        echo "   5. Se não há erros de digitação"
        exit 1
    fi
    
    # Verificar se a branch existe
    if ! git ls-remote --heads "$REPO_URL" | grep -q "refs/heads/$GITHUB_BRANCH"; then
        error "Branch '$GITHUB_BRANCH' não encontrada no repositório: $GITHUB_REPO"
        echo ""
        echo "🔍 Branches disponíveis:"
        git ls-remote --heads "$REPO_URL" | sed 's|.*refs/heads/||' | sort
        echo ""
        echo "💡 Use uma das branches listadas acima"
        exit 1
    fi
    
    success "Repositório GitHub validado: $GITHUB_REPO (branch: $GITHUB_BRANCH)"
fi

log "Criando site: $DOMAIN na porta $PORT"

# Criar estrutura de diretórios
SITE_DIR="/home/carlo/sites/$DOMAIN"
log "Criando estrutura de diretórios..."

mkdir -p "$SITE_DIR"/{public,logs,ssl,releases,shared,config}
mkdir -p "$SITE_DIR/public"/{static,templates}

# Criar deploy.sh padrão editável (apenas se não existir)
if [ ! -f "$SITE_DIR/deploy.sh" ]; then
    cat > "$SITE_DIR/deploy.sh" << 'EOF'
#!/bin/bash
# Deploy script para $DOMAIN
# Executado pelo Carlo Bolt (Deploy Now / Webhook)
# Como usar:
# - Ajuste os blocos comentados conforme seu framework/app
# - Prefira armazenar DB/arquivos em $SHARED_DIR para persistirem entre releases
# - Em falha crítica, faça "exit 1" para abortar o deploy

set -e

# Variáveis injetadas pelo pipeline (com defaults de segurança)
DOMAIN="${DOMAIN:-example.com}"
SITE_DIR="${SITE_DIR:-/home/carlo/sites/$DOMAIN}"
RELEASE_DIR="${RELEASE_DIR:-$SITE_DIR/current}"
CURRENT_DIR="${CURRENT_DIR:-$SITE_DIR/current}"
SHARED_DIR="${SHARED_DIR:-$SITE_DIR/shared}"
VENV="${VENV:-$RELEASE_DIR/venv}"
PYTHON_BIN="${PYTHON_BIN:-$VENV/bin/python}"
PORT="${PORT:-$(jq -r '.port // 5000' "$SITE_DIR/status.json" 2>/dev/null || echo 5000)}"
TIMESTAMP="${TIMESTAMP:-$(date +%Y%m%d_%H%M%S)}"

echo "[deploy.sh] DOMAIN=$DOMAIN"
echo "[deploy.sh] RELEASE_DIR=$RELEASE_DIR"

# 1) Navegar para a release (fallbacks seguros)
cd "$RELEASE_DIR" 2>/dev/null || cd "$SITE_DIR/public" 2>/dev/null || cd "$SITE_DIR"

# 2) Ativar venv da release, se existir
[ -f "$VENV/bin/activate" ] && source "$VENV/bin/activate"

# 3) Dependências Python (se houver requirements.txt)
if [ -f requirements.txt ]; then
  echo "[deploy.sh] Instalando dependências Python"
  pip install -r requirements.txt
fi

# 4) (Opcional) Backup SQLite antes de migrar
# DB_PATH="$SHARED_DIR/instance/app.db"
# if [ -f "$DB_PATH" ]; then
#   mkdir -p "$SHARED_DIR/backups"
#   BK_FILE="$SHARED_DIR/backups/app_${TIMESTAMP}.db"
#   cp -a "$DB_PATH" "$BK_FILE"
#   echo "[deploy.sh] Backup SQLite: $BK_FILE"
# fi

# 5) Blocos por framework (descomente os que se aplicam)

# Django:
# if [ -f manage.py ]; then
#   echo "[deploy.sh] Django: migrate"
#   "$PYTHON_BIN" manage.py migrate --noinput || true
#   echo "[deploy.sh] Django: collectstatic"
#   "$PYTHON_BIN" manage.py collectstatic --noinput || true
# fi

# Flask (migracao custom):
# if [ -f migrate_db.py ]; then
#   echo "[deploy.sh] Flask: migrate_db.py"
#   "$PYTHON_BIN" migrate_db.py || true
# fi

# Alembic (SQLAlchemy):
# if [ -f alembic.ini ]; then
#   echo "[deploy.sh] Alembic: upgrade head"
#   "$PYTHON_BIN" -m alembic upgrade head || true
# fi

# Celery (opcional):
# sudo supervisorctl restart "$DOMAIN-celery" || true
# sudo supervisorctl restart "$DOMAIN-celery-beat" || true

# 6) Iniciar/Reiniciar aplicação de forma inteligente
echo "[deploy.sh] Verificando status do supervisor..."
SUPERVISOR_STATUS=$(sudo supervisorctl status "$DOMAIN" 2>/dev/null | grep -o "RUNNING\\|STOPPED\\|FATAL" || echo "NOT_FOUND")

echo "[deploy.sh] Supervisor status: $SUPERVISOR_STATUS"

if [ "$SUPERVISOR_STATUS" = "NOT_FOUND" ]; then
    echo "[deploy.sh] Processo não encontrado, recarregando configuração..."
    sudo supervisorctl reread
    sudo supervisorctl update
    sudo supervisorctl start "$DOMAIN"
elif [ "$SUPERVISOR_STATUS" = "RUNNING" ]; then
    echo "[deploy.sh] Reiniciando processo em execução..."
    sudo supervisorctl restart "$DOMAIN"
else
    echo "[deploy.sh] Iniciando processo parado..."
    sudo supervisorctl start "$DOMAIN"
fi

echo "[deploy.sh] Concluído"
EOF
    chmod 755 "$SITE_DIR/deploy.sh"
fi

# Baixar código do GitHub se especificado
if [ -n "$GITHUB_REPO" ]; then
    log "Baixando código do GitHub: $GITHUB_REPO (branch: $GITHUB_BRANCH)"
    
    # Usar a URL determinada na validação
    if [ -z "$REPO_URL" ]; then
        REPO_URL="https://github.com/$GITHUB_REPO.git"
    fi
    
    # Criar diretório temporário para o clone
    TEMP_DIR="/tmp/carlo_github_$$"
    mkdir -p "$TEMP_DIR"
    
    # Clonar repositório
    if git clone -b "$GITHUB_BRANCH" "$REPO_URL" "$TEMP_DIR"; then
        log "Código baixado com sucesso"
        
        # Copiar arquivos do repositório para public/
        if [ -d "$TEMP_DIR" ]; then
            # Copiar todos os arquivos, exceto .git
            cp -r "$TEMP_DIR"/* "$SITE_DIR/public/" 2>/dev/null || true
            cp -r "$TEMP_DIR"/.* "$SITE_DIR/public/" 2>/dev/null || true
            
            # Remover .git se foi copiado
            rm -rf "$SITE_DIR/public/.git" 2>/dev/null || true
            
            log "Arquivos copiados do repositório"
        fi
        
        # Limpar diretório temporário
        rm -rf "$TEMP_DIR"
    else
        error "Falha ao baixar código do GitHub"
        echo "Verifique se o repositório e branch estão corretos"
        exit 1
    fi
fi

# Criar arquivo de configuração do site
cat > "$SITE_DIR/config/site.conf" << EOF
# Configuração do site $DOMAIN
DOMAIN=$DOMAIN
PORT=$PORT
PYTHON_VERSION=$PYTHON_VERSION
FRAMEWORK=$FRAMEWORK
CREATED_AT=$(date +'%Y-%m-%d %H:%M:%S')
STATUS=stopped
EOF

# Criar app Python básico baseado no framework (só se não existir)
if [ ! -f "$SITE_DIR/public/app.py" ]; then
    log "Criando app.py padrão para $FRAMEWORK"
    case $FRAMEWORK in
        flask)
            cat > "$SITE_DIR/public/app.py" << 'EOF'
from flask import Flask, render_template
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
            .info { background: rgba(255,255,255,0.05); padding: 15px; border-radius: 8px; margin: 10px 0; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🚀 Site Python Funcionando!</h1>
            <div class="status">
                <h2>✅ Status: Online</h2>
                <p>Seu site Python está rodando com sucesso no Carlo Deploy</p>
            </div>
            <div class="info">
                <h3>📊 Informações do Site</h3>
                <p><strong>Framework:</strong> Flask</p>
                <p><strong>Python:</strong> 3.12</p>
                <p><strong>Porta:</strong> ''' + os.environ.get('PORT', '5000') + '''</p>
                <p><strong>Data de criação:</strong> ''' + os.environ.get('SITE_CREATED', 'N/A') + '''</p>
            </div>
            <div class="info">
                <h3>🔧 Próximos Passos</h3>
                <p>1. Configure seu domínio no DNS</p>
                <p>2. Ative o SSL com Let's Encrypt</p>
                <p>3. Configure seu banco de dados</p>
                <p>4. Faça deploy do seu código</p>
            </div>
        </div>
    </body>
    </html>
    '''

@app.route('/health')
def health():
    return {'status': 'healthy', 'framework': 'flask'}

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 5000)), debug=False)
EOF
            ;;
        
        django)
            cat > "$SITE_DIR/public/app.py" << 'EOF'
import os
import sys
import django
from django.core.management import execute_from_command_line

# Configurar Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'myproject.settings')
django.setup()

# Criar projeto Django básico
if not os.path.exists('myproject'):
    execute_from_command_line(['manage.py', 'startproject', 'myproject', '.'])

# Rodar servidor
if __name__ == '__main__':
    execute_from_command_line(['manage.py', 'runserver', '0.0.0.0:5000'])
EOF
            ;;
        
        fastapi)
            cat > "$SITE_DIR/public/app.py" << 'EOF'
from fastapi import FastAPI
from fastapi.responses import HTMLResponse
import uvicorn

app = FastAPI(title="Site Python - Carlo Deploy")

@app.get("/", response_class=HTMLResponse)
async def root():
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
            .info { background: rgba(255,255,255,0.05); padding: 15px; border-radius: 8px; margin: 10px 0; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🚀 Site Python Funcionando!</h1>
            <div class="status">
                <h2>✅ Status: Online</h2>
                <p>Seu site Python está rodando com sucesso no Carlo Deploy</p>
            </div>
            <div class="info">
                <h3>📊 Informações do Site</h3>
                <p><strong>Framework:</strong> FastAPI</p>
                <p><strong>Python:</strong> 3.12</p>
                <p><strong>Porta:</strong> ''' + os.environ.get('PORT', '5000') + '''</p>
                <p><strong>Data de criação:</strong> N/A</p>
            </div>
            <div class="info">
                <h3>🔧 Próximos Passos</h3>
                <p>1. Configure seu domínio no DNS</p>
                <p>2. Ative o SSL com Let's Encrypt</p>
                <p>3. Configure seu banco de dados</p>
                <p>4. Faça deploy do seu código</p>
            </div>
        </div>
    </body>
    </html>
    '''

if __name__ == '__main__':
    uvicorn.run(app, host='0.0.0.0', port=5000)
EOF
            ;;
        
        *)
            cat > "$SITE_DIR/public/app.py" << 'EOF'
#!/usr/bin/env python3
print("Site Python - Carlo Deploy")
print("Configure seu app.py personalizado")
EOF
            ;;
    esac
else
    log "app.py já existe (vindo do repositório GitHub)"
fi

# Criar requirements.txt (só se não existir)
if [ ! -f "$SITE_DIR/public/requirements.txt" ]; then
    log "Criando requirements.txt padrão para $FRAMEWORK"
    cat > "$SITE_DIR/public/requirements.txt" << EOF
# Requirements para $DOMAIN
# Framework: $FRAMEWORK
# Python: $PYTHON_VERSION

EOF

    case $FRAMEWORK in
        flask)
            echo "Flask==3.0.0" >> "$SITE_DIR/public/requirements.txt"
            echo "Werkzeug==3.0.1" >> "$SITE_DIR/public/requirements.txt"
            echo "gunicorn==21.2.0" >> "$SITE_DIR/public/requirements.txt"
            ;;
        django)
            echo "Django==5.0.0" >> "$SITE_DIR/public/requirements.txt"
            echo "gunicorn==21.2.0" >> "$SITE_DIR/public/requirements.txt"
            ;;
        fastapi)
            echo "fastapi==0.104.1" >> "$SITE_DIR/public/requirements.txt"
            echo "uvicorn==0.24.0" >> "$SITE_DIR/public/requirements.txt"
            echo "gunicorn==21.2.0" >> "$SITE_DIR/public/requirements.txt"
            ;;
    esac
else
    log "requirements.txt já existe (vindo do repositório GitHub)"
fi

# Criar virtual environment
log "Criando ambiente virtual Python..."

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

log "Usando Python: $PYTHON_CMD ($($PYTHON_CMD --version 2>&1))"

cd "$SITE_DIR/public"

# Criar ambiente virtual com caminho explícito
if ! $PYTHON_CMD -m venv venv; then
    error "Falha ao criar ambiente virtual Python"
    echo "Verifique se python3-venv está instalado: sudo apt install python3-venv"
    exit 1
fi

# Instalar dependências
log "Instalando dependências..."
source venv/bin/activate

# Verificar se pip está disponível
if ! command -v pip &> /dev/null; then
    log "Pip não encontrado, instalando..."
    $PYTHON_CMD -m ensurepip --upgrade
fi

pip install --upgrade pip
pip install -r requirements.txt

# Criar arquivo de configuração do Gunicorn
cat > "$SITE_DIR/gunicorn.conf" << EOF
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

# Criar arquivo de configuração do supervisor
SUPERVISOR_CONF="/etc/supervisor/conf.d/$DOMAIN.conf"
log "Configurando supervisor..."

# Para sites GitHub, usar sistema de releases; para outros, usar public/
if [ -n "$GITHUB_REPO" ]; then
    # Configuração para sites GitHub (sistema de releases)
    sudo tee "$SUPERVISOR_CONF" > /dev/null << EOF
[program:$DOMAIN]
command=$SITE_DIR/current/venv/bin/gunicorn -c $SITE_DIR/current/gunicorn.conf app:app
directory=$SITE_DIR/current
user=vito
autostart=false
autorestart=true
redirect_stderr=true
stdout_logfile=$SITE_DIR/logs/app.log
environment=PORT=$PORT,GITHUB_REPO="$GITHUB_REPO",GITHUB_BRANCH="$GITHUB_BRANCH"
EOF
else
    # Configuração para sites manuais (public/)
    sudo tee "$SUPERVISOR_CONF" > /dev/null << EOF
[program:$DOMAIN]
command=$SITE_DIR/public/venv/bin/gunicorn -c $SITE_DIR/gunicorn.conf app:app
directory=$SITE_DIR/public
user=vito
autostart=false
autorestart=true
redirect_stderr=true
stdout_logfile=$SITE_DIR/logs/app.log
environment=PORT=$PORT,SITE_CREATED="$(date +'%Y-%m-%d %H:%M:%S')"
EOF
fi

# Criar configuração Nginx
NGINX_CONF="/home/carlo/nginx/sites-available/$DOMAIN"
log "Configurando Nginx..."

cat > "$NGINX_CONF" << EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    
    # Logs
    access_log $SITE_DIR/logs/access.log;
    error_log $SITE_DIR/logs/error.log;
    
    # Let's Encrypt validation
    location /.well-known/acme-challenge/ {
        root /home/carlo/webroot;
    }
    
    # Proxy para Python
    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Arquivos estáticos
    location /static/ {
        alias $SITE_DIR/current/static/;
        expires 30d;
    }
}
EOF

# Ativar site no Nginx
if [ ! -L "/etc/nginx/sites-enabled/$DOMAIN" ]; then
    sudo ln -s "$NGINX_CONF" "/etc/nginx/sites-enabled/"
fi

# Testar configuração Nginx
if sudo nginx -t; then
    sudo systemctl reload nginx
    success "Configuração Nginx carregada"
else
    error "Erro na configuração Nginx"
fi

# Recarregar supervisor
sudo supervisorctl reread
sudo supervisorctl update

# Criar arquivo de status
if [ -n "$GITHUB_REPO" ]; then
    cat > "$SITE_DIR/status.json" << EOF
{
    "domain": "$DOMAIN",
    "port": $PORT,
    "framework": "$FRAMEWORK",
    "python_version": "$PYTHON_VERSION",
    "status": "created",
    "created_at": "$(date -Iseconds)",
    "last_started": null,
    "last_stopped": null,
    "github_repo": "$GITHUB_REPO",
    "github_branch": "$GITHUB_BRANCH"
}
EOF
else
    cat > "$SITE_DIR/status.json" << EOF
{
    "domain": "$DOMAIN",
    "port": $PORT,
    "framework": "$FRAMEWORK",
    "python_version": "$PYTHON_VERSION",
    "status": "created",
    "created_at": "$(date -Iseconds)",
    "last_started": null,
    "last_stopped": null
}
EOF
fi

# Definir permissões
sudo chown -R vito:vito "$SITE_DIR"
chmod -R 755 "$SITE_DIR"

success "Site $DOMAIN criado com sucesso!"
echo ""
echo "📋 Informações do site:"
echo "   Domínio: $DOMAIN"
echo "   Porta: $PORT"
echo "   Framework: $FRAMEWORK"
echo "   Python: $PYTHON_VERSION"
echo "   Diretório: $SITE_DIR"
echo ""
echo "🚀 Para iniciar o site:"
echo "   sudo supervisorctl start $DOMAIN"
echo ""
echo "🌐 Para acessar:"
echo "   http://$DOMAIN (após configurar DNS)"
echo "   http://localhost:$PORT (localmente)"
echo ""
echo "📝 Logs disponíveis em:"
echo "   $SITE_DIR/logs/"

# Configurar GitHub se especificado
if [ -n "$GITHUB_REPO" ]; then
    echo ""
    echo "🔗 Configurando integração GitHub..."
    echo "   Repositório: $GITHUB_REPO"
    echo "   Branch: $GITHUB_BRANCH"
    
    # Usar a URL determinada na validação
    if [ -z "$REPO_URL" ]; then
        REPO_URL="https://github.com/$GITHUB_REPO.git"
    fi
    
    # Criar diretório config se não existir
    mkdir -p "$SITE_DIR/config"
    
    # Criar arquivo github.conf para compatibilidade
    cat > "$SITE_DIR/config/github.conf" << EOF
# Configuração GitHub para $DOMAIN
GITHUB_REPO="$GITHUB_REPO"
GITHUB_BRANCH="$GITHUB_BRANCH"
EOF
    
    # Fazer apenas git pull se GitHub foi especificado
    echo ""
    echo "📥 Baixando código do GitHub..."
    cd "$SITE_DIR"
    if git clone -b "$GITHUB_BRANCH" "$REPO_URL" . 2>/dev/null || git pull origin "$GITHUB_BRANCH" 2>/dev/null; then
        success "Código baixado com sucesso!"
        echo "   ✅ Repositório: $GITHUB_REPO"
        echo "   ✅ Branch: $GITHUB_BRANCH"
        echo "   ✅ Diretório: $SITE_DIR"
    else
        warning "Falha ao baixar código do GitHub"
        echo "   ⚠️  Execute manualmente: git clone -b $GITHUB_BRANCH https://github.com/$GITHUB_REPO.git ."
    fi
    
    echo ""
    echo "📋 Próximos passos:"
    echo "   1. Configure os arquivos .env, gunicorn.conf.py, supervisor.conf"
    echo "   2. Execute o primeiro deploy manualmente"
    echo "   3. Configure o webhook para auto-deploy"
    echo ""
    echo "💡 Comandos úteis:"
    echo "   ./carlo-github-setup.sh $DOMAIN $GITHUB_REPO    # Configurar GitHub"
    echo "   ./carlo-deploy.sh $DOMAIN $GITHUB_BRANCH                  # Deploy manual"
    echo "   ./carlo-rollback.sh $DOMAIN                     # Rollback"
fi 