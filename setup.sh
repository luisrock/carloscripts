#!/bin/bash
# ========================================
# CARLO SETUP SCRIPT
# ========================================
# Prepara o ambiente Carlo para uso
# Uso: ./setup.sh

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

echo -e "${CYAN}🚀 CONFIGURANDO SISTEMA CARLO${NC}"
echo "=================================="
echo ""

# Verificar se estamos no diretório correto
if [ ! -f "carlo-create-site.sh" ]; then
    error "Execute este script no diretório dos scripts Carlo"
    echo "Diretório atual: $(pwd)"
    exit 1
fi

log "Verificando dependências..."

# Verificar se jq está instalado
if ! command -v jq &> /dev/null; then
    warning "jq não encontrado, instalando..."
    sudo apt update
    sudo apt install -y jq
fi

# Verificar se supervisor está instalado
if ! command -v supervisorctl &> /dev/null; then
    warning "supervisor não encontrado, instalando..."
    sudo apt update
    sudo apt install -y supervisor
    sudo systemctl enable supervisor
    sudo systemctl start supervisor
fi

# Verificar se nginx está instalado
if ! command -v nginx &> /dev/null; then
    warning "nginx não encontrado, instalando..."
    sudo apt update
    sudo apt install -y nginx
    sudo systemctl enable nginx
    sudo systemctl start nginx
fi

# Verificar se python3 está instalado
if ! command -v python3 &> /dev/null; then
    warning "Python 3 não encontrado, instalando..."
    sudo apt update
    sudo apt install -y python3 python3-pip python3-venv python3-dev
fi

# Verificar se python3-venv está instalado
if ! python3 -c "import venv" 2>/dev/null; then
    warning "python3-venv não encontrado, instalando..."
    sudo apt update
    sudo apt install -y python3-venv
fi

# Verificar se pip3 está instalado
if ! command -v pip3 &> /dev/null; then
    warning "pip3 não encontrado, instalando..."
    sudo apt update
    sudo apt install -y python3-pip
fi

# Testar se Python está funcionando
if ! python3 --version &> /dev/null; then
    error "Python 3 não está funcionando corretamente"
    echo "Execute: sudo apt install python3 python3-pip python3-venv"
    exit 1
fi

success "Python 3 verificado: $(python3 --version)"

success "Dependências verificadas"

log "Criando estrutura de diretórios..."

# Criar estrutura Carlo
sudo mkdir -p /home/carlo/{sites,scripts,logs,nginx/{sites-available,sites-enabled,templates},backups,ssl,databases}
sudo chown -R vito:vito /home/carlo

# Criar diretório de backups
sudo mkdir -p /home/carlo/backups/{deleted_sites,databases,logs}
sudo chown -R vito:vito /home/carlo/backups

success "Estrutura de diretórios criada"

log "Configurando permissões dos scripts..."

# Tornar scripts executáveis
chmod +x *.sh

# Copiar scripts para o diretório Carlo
sudo cp *.sh /home/carlo/scripts/
sudo chown vito:vito /home/carlo/scripts/*.sh
sudo chmod +x /home/carlo/scripts/*.sh

success "Scripts configurados"

log "Configurando swap (opcional)..."

# Verificar se swap já existe
if ! swapon --show | grep -q "/swapfile"; then
    if [ ! -f "/swapfile" ]; then
        warning "Configurando swap de 2GB..."
        sudo fallocate -l 2G /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        
        # Adicionar ao fstab
        if ! grep -q "/swapfile" /etc/fstab; then
            echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
        fi
        
        success "Swap configurado"
    else
        warning "Arquivo swap já existe, ativando..."
        sudo swapon /swapfile
    fi
else
    success "Swap já está ativo"
fi

log "Configurando logrotate..."

# Criar configuração do logrotate para sites Carlo
sudo tee /etc/logrotate.d/carlo-sites > /dev/null << 'EOF'
/home/carlo/sites/*/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 vito vito
    postrotate
        sudo systemctl reload nginx
    endscript
}
EOF

success "Logrotate configurado"

log "Verificando configuração do supervisor..."

# Verificar se o supervisor está configurado corretamente
if [ ! -f "/etc/supervisor/conf.d/supervisord.conf" ]; then
    warning "Configurando supervisor..."
    sudo tee /etc/supervisor/conf.d/supervisord.conf > /dev/null << 'EOF'
[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock

[unix_http_server]
file=/var/run/supervisor.sock
chmod=0700

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock
EOF
fi

# Recarregar supervisor
sudo supervisorctl reread
sudo supervisorctl update

success "Supervisor configurado"

log "Testando scripts..."

# Testar script de estatísticas
if ./carlo-stats.sh --json > /dev/null 2>&1; then
    success "Script de estatísticas funcionando"
else
    warning "Script de estatísticas com problemas"
fi

# Testar listagem de sites
if ./carlo-list-sites.sh --json > /dev/null 2>&1; then
    success "Script de listagem funcionando"
else
    warning "Script de listagem com problemas"
fi

echo ""
echo -e "${CYAN}✅ CONFIGURAÇÃO CONCLUÍDA${NC}"
echo ""
echo "📋 Resumo da configuração:"
echo "   ✅ Dependências instaladas"
echo "   ✅ Estrutura de diretórios criada"
echo "   ✅ Scripts configurados"
echo "   ✅ Swap configurado (2GB)"
echo "   ✅ Logrotate configurado"
echo "   ✅ Supervisor configurado"
echo ""
echo "📁 Diretórios criados:"
echo "   /home/carlo/sites/           # Sites Python"
echo "   /home/carlo/scripts/         # Scripts Carlo"
echo "   /home/carlo/logs/            # Logs do sistema"
echo "   /home/carlo/nginx/           # Configurações Nginx"
echo "   /home/carlo/backups/         # Backups"
echo "   /home/carlo/ssl/             # Certificados SSL"
echo "   /home/carlo/databases/       # Bancos de dados"
echo ""
echo "🚀 Próximos passos:"
echo "   1. Criar um site de teste:"
echo "      ./carlo-create-site.sh teste.com 5000 3.12 flask"
echo ""
echo "   2. Iniciar o site:"
echo "      ./carlo-start-site.sh teste.com"
echo ""
echo "   3. Verificar estatísticas:"
echo "      ./carlo-stats.sh"
echo ""
echo "   4. Listar sites:"
echo "      ./carlo-list-sites.sh"
echo ""
echo "💡 Comandos úteis:"
echo "   ./carlo-create-site.sh <domain> <port> [python_version] [framework]"
echo "   ./carlo-list-sites.sh [--json] [--status]"
echo "   ./carlo-start-site.sh <domain>"
echo "   ./carlo-stop-site.sh <domain>"
echo "   ./carlo-delete-site.sh <domain>"
echo "   ./carlo-logs.sh <domain> [--follow]"
echo "   ./carlo-stats.sh [--json] [--detailed]"
echo ""
echo -e "${GREEN}🎉 Sistema Carlo pronto para uso!${NC}" 