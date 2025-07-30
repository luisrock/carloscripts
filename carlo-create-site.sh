#!/bin/bash
# ========================================
# CARLO CREATE SITE SCRIPT
# ========================================
# Cria um novo site Python/Flask no sistema Carlo
# Uso: ./carlo-create-site.sh <domain> <port> [python_version] [framework]
# Exemplo: ./carlo-create-site.sh meusite.com 5000 3.12 flask

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

# Verificar argumentos
if [ $# -lt 2 ]; then
    error "Uso: $0 <domain> <port> [python_version] [framework] [--github repo]"
    echo "Exemplo: $0 meusite.com 5000 3.12 flask"
    echo "         $0 meusite.com 5000 3.12 flask --github usuario/repositorio"
    exit 1
fi

DOMAIN=$1
PORT=$2
PYTHON_VERSION=${3:-3.12}
FRAMEWORK=${4:-flask}
GITHUB_REPO=""

# Verificar se --github foi passado
if [[ "$*" == *"--github"* ]]; then
    for i in "${!@}"; do
        if [ "${!i}" = "--github" ] && [ $((i+1)) -le $# ]; then
            GITHUB_REPO="${!((i+1))}"
            break
        fi
    done
fi

# Validar domínio
if [[ ! $DOMAIN =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    error "Domínio inválido: $DOMAIN"
fi

# Validar porta
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1000 ] || [ "$PORT" -gt 9999 ]; then
    error "Porta inválida: $PORT (deve ser entre 1000-9999)"
fi

# Verificar se porta já está em uso
if netstat -tuln | grep -q ":$PORT "; then
    error "Porta $PORT já está em uso"
fi

# Verificar se domínio já existe
if [ -d "/home/carlo/sites/$DOMAIN" ]; then
    error "Site $DOMAIN já existe"
fi

log "Criando site: $DOMAIN na porta $PORT"

# Criar estrutura de diretórios
SITE_DIR="/home/carlo/sites/$DOMAIN"
log "Criando estrutura de diretórios..."

mkdir -p "$SITE_DIR"/{public,logs,ssl,releases,shared,config}
mkdir -p "$SITE_DIR/public"/{static,templates}

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

# Criar app Python básico baseado no framework
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
                <p><strong>Porta:</strong> 5000</p>
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
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🚀 Site Python Funcionando!</h1>
            <div class="status">
                <h2>✅ Status: Online</h2>
                <p>Seu site Python está rodando com sucesso no Carlo Deploy</p>
                <p><strong>Framework:</strong> FastAPI</p>
            </div>
        </div>
    </body>
    </html>
    '''

@app.get("/health")
async def health():
    return {"status": "healthy", "framework": "fastapi"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=5000)
EOF
        ;;
    
    *)
        error "Framework não suportado: $FRAMEWORK (use: flask, django, fastapi)"
        ;;
esac

# Criar requirements.txt
cat > "$SITE_DIR/public/requirements.txt" << EOF
# Requirements para $DOMAIN
# Framework: $FRAMEWORK
# Python: $PYTHON_VERSION

EOF

case $FRAMEWORK in
    flask)
        echo "Flask==3.0.0" >> "$SITE_DIR/public/requirements.txt"
        echo "Werkzeug==3.0.1" >> "$SITE_DIR/public/requirements.txt"
        ;;
    django)
        echo "Django==5.0.0" >> "$SITE_DIR/public/requirements.txt"
        ;;
    fastapi)
        echo "fastapi==0.104.1" >> "$SITE_DIR/public/requirements.txt"
        echo "uvicorn==0.24.0" >> "$SITE_DIR/public/requirements.txt"
        ;;
esac

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

# Criar arquivo de configuração do supervisor
SUPERVISOR_CONF="/etc/supervisor/conf.d/$DOMAIN.conf"
log "Configurando supervisor..."

sudo tee "$SUPERVISOR_CONF" > /dev/null << EOF
[program:$DOMAIN]
command=$SITE_DIR/public/venv/bin/python $SITE_DIR/public/app.py
directory=$SITE_DIR/public
user=vito
autostart=false
autorestart=true
redirect_stderr=true
stdout_logfile=$SITE_DIR/logs/app.log
environment=PORT=$PORT,SITE_CREATED="$(date +'%Y-%m-%d %H:%M:%S')"
EOF

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
        alias $SITE_DIR/public/static/;
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
    echo "   Branch: main"
    echo ""
    echo "📋 Próximos passos:"
    echo "   1. Configure o webhook no GitHub"
    echo "   2. Execute: ./carlo-deploy.sh $DOMAIN main"
    echo "   3. Faça push para trigger automático"
    echo ""
    echo "💡 Comandos úteis:"
    echo "   ./carlo-github-setup.sh $DOMAIN $GITHUB_REPO    # Configurar GitHub"
    echo "   ./carlo-deploy.sh $DOMAIN main                  # Deploy manual"
    echo "   ./carlo-rollback.sh $DOMAIN                     # Rollback"
fi 