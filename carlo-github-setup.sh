#!/bin/bash
# ========================================
# CARLO GITHUB SETUP SCRIPT
# ========================================
# Configura integração com GitHub para deploy automático
# Uso: ./carlo-github-setup.sh <domain> <repo> [branch] [webhook_secret]

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
if [ $# -lt 2 ]; then
    error "Uso: $0 <domain> <repo> [branch] [webhook_secret]"
    echo "Exemplo: $0 meusite.com usuario/repositorio"
    echo "         $0 meusite.com usuario/repositorio develop"
    echo "         $0 meusite.com usuario/repositorio main secret123"
    exit 1
fi

DOMAIN=$1
GITHUB_REPO=$2
BRANCH=${3:-main}
WEBHOOK_SECRET=${4:-$(openssl rand -hex 32)}

SITE_DIR="/home/carlo/sites/$DOMAIN"

# Verificar se o site existe
if [ ! -d "$SITE_DIR" ]; then
    error "Site $DOMAIN não encontrado"
    echo "Execute: ./carlo-create-site.sh $DOMAIN <port> para criar o site"
    exit 1
fi

log "Configurando GitHub para $DOMAIN"

# Verificar se git está instalado
if ! command -v git &> /dev/null; then
    warning "Git não encontrado, instalando..."
    sudo apt update
    sudo apt install -y git
fi

# Criar diretório de configuração se não existir
mkdir -p "$SITE_DIR/config"

# Salvar configuração GitHub
log "Salvando configuração GitHub..."
cat > "$SITE_DIR/config/github.conf" << EOF
# Configuração GitHub para $DOMAIN
GITHUB_REPO="$GITHUB_REPO"
GITHUB_BRANCH="$BRANCH"
WEBHOOK_SECRET="$WEBHOOK_SECRET"
WEBHOOK_URL="https://$DOMAIN/webhook"
EOF

# Criar diretório de releases
mkdir -p "$SITE_DIR/releases"

# Criar diretório compartilhado
mkdir -p "$SITE_DIR/shared"

# Testar acesso ao repositório
log "Testando acesso ao repositório GitHub..."
if git ls-remote https://github.com/$GITHUB_REPO.git > /dev/null 2>&1; then
    success "Repositório acessível"
else
    error "Não foi possível acessar o repositório: $GITHUB_REPO"
    echo "Verifique:"
    echo "   1. Se o repositório existe"
    echo "   2. Se é público ou você tem acesso"
    echo "   3. Se o nome está correto (usuario/repositorio)"
    exit 1
fi

# Clonar repositório
log "Clonando repositório..."
if [ -d "$SITE_DIR/repo" ]; then
    warning "Repositório já existe, atualizando..."
    cd "$SITE_DIR/repo"
    git fetch origin
    git reset --hard origin/$BRANCH
else
    git clone -b $BRANCH https://github.com/$GITHUB_REPO.git "$SITE_DIR/repo"
fi

# Verificar se app.py existe no repositório
if [ ! -f "$SITE_DIR/repo/app.py" ]; then
    warning "app.py não encontrado no repositório"
    echo "Criando app.py básico..."
    cat > "$SITE_DIR/repo/app.py" << 'EOF'
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
            <h1>🚀 Site Python via GitHub!</h1>
            <div class="status">
                <h2>✅ Integração GitHub Funcionando</h2>
                <p>Seu site está conectado ao GitHub</p>
                <p><strong>Repositório:</strong> ''' + os.environ.get('GITHUB_REPO', 'N/A') + '''</p>
                <p><strong>Branch:</strong> ''' + os.environ.get('GITHUB_BRANCH', 'main') + '''</p>
            </div>
        </div>
    </body>
    </html>
    '''

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 5000)), debug=False)
EOF
    
    # Commit do arquivo básico
    cd "$SITE_DIR/repo"
    git add app.py
    git config user.email "carlo@deploy.local"
    git config user.name "Carlo Deploy"
    git commit -m "Add basic app.py for Carlo Deploy" 2>/dev/null || true
    git push origin $BRANCH 2>/dev/null || warning "Não foi possível fazer push (repositório pode ser somente leitura)"
fi

# Verificar se requirements.txt existe
if [ ! -f "$SITE_DIR/repo/requirements.txt" ]; then
    warning "requirements.txt não encontrado, criando básico..."
    cat > "$SITE_DIR/repo/requirements.txt" << EOF
# Requirements para $DOMAIN
Flask==3.0.0
Werkzeug==3.0.1
EOF
    
    # Commit do requirements.txt
    cd "$SITE_DIR/repo"
    git add requirements.txt
    git commit -m "Add requirements.txt for Carlo Deploy" 2>/dev/null || true
    git push origin $BRANCH 2>/dev/null || warning "Não foi possível fazer push"
fi

# Criar webhook endpoint (será usado pela interface web)
log "Configurando webhook..."
WEBHOOK_ENDPOINT="/webhook"
WEBHOOK_URL="https://$DOMAIN$WEBHOOK_ENDPOINT"

# Criar arquivo de configuração do webhook
cat > "$SITE_DIR/config/webhook.conf" << EOF
# Configuração do webhook para $DOMAIN
WEBHOOK_ENDPOINT="$WEBHOOK_ENDPOINT"
WEBHOOK_SECRET="$WEBHOOK_SECRET"
WEBHOOK_URL="$WEBHOOK_URL"
EOF

# Atualizar status do site
PORT=$(jq -r '.port // 5000' "$SITE_DIR/status.json" 2>/dev/null || echo "5000")
cat > "$SITE_DIR/status.json" << EOF
{
    "domain": "$DOMAIN",
    "port": $PORT,
    "framework": "github",
    "python_version": "3.12",
    "status": "configured",
    "created_at": "$(jq -r '.created_at // "'$(date -Iseconds)'"' "$SITE_DIR/status.json" 2>/dev/null || echo "$(date -Iseconds)")",
    "github_repo": "$GITHUB_REPO",
    "github_branch": "$BRANCH",
    "webhook_url": "$WEBHOOK_URL",
    "webhook_secret": "$WEBHOOK_SECRET"
}
EOF

success "GitHub configurado com sucesso!"

echo ""
echo "📋 Informações da configuração:"
echo "   Domínio: $DOMAIN"
echo "   Repositório: $GITHUB_REPO"
echo "   Branch: $BRANCH"
echo "   Webhook URL: $WEBHOOK_URL"
echo "   Webhook Secret: $WEBHOOK_SECRET"
echo ""
echo "🚀 Próximos passos:"
echo "   1. Configure o webhook no GitHub:"
echo "      - Vá para Settings > Webhooks"
echo "      - Adicione: $WEBHOOK_URL"
echo "      - Secret: $WEBHOOK_SECRET"
echo "      - Events: Just the push event"
echo ""
echo "   2. Faça o primeiro deploy:"
echo "      ./carlo-deploy.sh $DOMAIN $BRANCH"
echo ""
echo "   3. Teste o webhook fazendo um push:"
echo "      git push origin $BRANCH"
echo ""
echo "🔧 Comandos úteis:"
echo "   ./carlo-deploy.sh $DOMAIN $BRANCH    # Deploy manual"
echo "   ./carlo-logs.sh $DOMAIN --follow     # Ver logs"
echo "   ./carlo-stats.sh                     # Ver estatísticas"
echo ""
echo "💡 Dicas:"
echo "   - O webhook será processado pela interface web"
echo "   - Cada push para $BRANCH fará deploy automático"
echo "   - Mantenha o secret seguro"
echo "   - Use branches diferentes para staging/production" 