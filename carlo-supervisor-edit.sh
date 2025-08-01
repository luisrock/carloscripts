#!/bin/bash
# ========================================
# CARLO SUPERVISOR EDIT SCRIPT
# ========================================
# Lê, edita e salva configurações Supervisor para sites Python
# Uso: ./carlo-supervisor-edit.sh <domain> [--read|--write --content <content>]

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
ACTION=""
DOMAIN=""
CONFIG_CONTENT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --read)
            ACTION="read"
            shift
            ;;
        --write)
            ACTION="write"
            shift
            ;;
        --content)
            CONFIG_CONTENT="$2"
            shift 2
            ;;
        *)
            if [[ -z "$DOMAIN" ]]; then
                DOMAIN="$1"
            else
                error "Argumento desconhecido: $1"
            fi
            shift
            ;;
    esac
done

# Verificar se o domínio foi fornecido
if [[ -z "$DOMAIN" ]]; then
    error "Domínio é obrigatório"
fi

# Definir caminhos
SITE_DIR="/home/carlo/sites/$DOMAIN"
BACKUP_DIR="$SITE_DIR/backups"
SUPERVISOR_CONF="/etc/supervisor/conf.d/$DOMAIN.conf"

# Função para criar backup
create_backup() {
    if [[ ! -f "$SUPERVISOR_CONF" ]]; then
        return
    fi
    
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_NAME="supervisor_backup_${TIMESTAMP}.conf"
    BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"
    
    if sudo cp "$SUPERVISOR_CONF" "$BACKUP_PATH"; then
        log "Backup criado: $BACKUP_NAME"
        echo "$BACKUP_PATH"
    else
        error "Falha ao criar backup"
    fi
}

# Função para validar conteúdo Supervisor
validate_supervisor_content() {
    local content="$1"
    local errors=0
    
    # Verificar se tem seção [program:domain]
    if ! echo "$content" | grep -q "^[[:space:]]*\[program:$DOMAIN\]"; then
        warning "Seção [program:$DOMAIN] não encontrada"
        ((errors++))
    fi
    
    # Verificar configurações obrigatórias
    if ! echo "$content" | grep -q "^[[:space:]]*command[[:space:]]*="; then
        warning "Configuração 'command' não encontrada"
        ((errors++))
    fi
    
    if ! echo "$content" | grep -q "^[[:space:]]*directory[[:space:]]*="; then
        warning "Configuração 'directory' não encontrada"
        ((errors++))
    fi
    
    if ! echo "$content" | grep -q "^[[:space:]]*user[[:space:]]*="; then
        warning "Configuração 'user' não encontrada"
        ((errors++))
    fi
    
    return $errors
}

# Função para ler arquivo Supervisor
read_supervisor_file() {
    if [[ ! -f "$SUPERVISOR_CONF" ]]; then
        echo "# Configuração Supervisor para $DOMAIN"
        echo "# Adicione suas configurações do supervisor aqui"
        echo "# Exemplo:"
        echo "[program:$DOMAIN]"
        echo "command = $SITE_DIR/public/venv/bin/python $SITE_DIR/public/app.py"
        echo "directory = $SITE_DIR/public"
        echo "user = vito"
        echo "autostart = true"
        echo "autorestart = true"
        echo "redirect_stderr = true"
        echo "stdout_logfile = $SITE_DIR/logs/app.log"
        return
    fi
    
    # Ler conteúdo do arquivo sem incluir logs e garantir quebra de linha no final
    sudo cat "$SUPERVISOR_CONF" 2>/dev/null
    echo ""  # Garantir quebra de linha no final
}

# Função para escrever arquivo Supervisor
write_supervisor_file() {
    local content="$1"
    
    # Verificar se o diretório do site existe
    if [[ ! -d "$SITE_DIR" ]]; then
        error "Diretório do site não encontrado: $SITE_DIR"
    fi
    
    # Validar conteúdo
    if ! validate_supervisor_content "$content"; then
        warning "Problemas de validação encontrados no conteúdo Supervisor"
    fi
    
    # Criar backup antes de alterar
    local backup_path=$(create_backup)
    
    # Escrever novo conteúdo usando sudo (interpretar \n como quebras de linha)
    if printf "%b" "$content" | sudo tee "$SUPERVISOR_CONF" > /dev/null; then
        sudo chmod 644 "$SUPERVISOR_CONF"
        log "Arquivo supervisor.conf salvo com sucesso para $DOMAIN"
        log "Localização: $SUPERVISOR_CONF"
        if [[ -n "$backup_path" ]]; then
            log "Backup disponível em: $backup_path"
        fi
        
        # Recarregar supervisor
        if sudo supervisorctl reread && sudo supervisorctl update; then
            log "Supervisor recarregado com sucesso"
            success "Configuração Supervisor atualizada"
        else
            warning "Falha ao recarregar supervisor"
            success "Configuração Supervisor salva (recarregue manualmente)"
        fi
    else
        error "Falha ao salvar arquivo supervisor.conf"
        
        # Tentar restaurar backup se existir
        if [[ -n "$backup_path" && -f "$backup_path" ]]; then
            if sudo cp "$backup_path" "$SUPERVISOR_CONF"; then
                warning "Arquivo supervisor.conf restaurado do backup"
            else
                error "Falha ao restaurar backup"
            fi
        fi
    fi
}

# Executar ação baseada nos argumentos
case "$ACTION" in
    "read")
        log "Lendo configuração Supervisor para $DOMAIN"
        echo "=== CONFIGURAÇÃO SUPERVISOR PARA $(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]') ==="
        read_supervisor_file
        if [[ -f "$SUPERVISOR_CONF" ]]; then
            log "Arquivo supervisor.conf lido com sucesso para $DOMAIN"
            log "Localização: $SUPERVISOR_CONF"
        else
            warning "Arquivo supervisor.conf não encontrado para $DOMAIN"
            log "Localização: $SUPERVISOR_CONF"
        fi
        echo "=== FIM DA CONFIGURAÇÃO ==="
        ;;
    "write")
        if [[ -z "$CONFIG_CONTENT" ]]; then
            error "Conteúdo é obrigatório para operação --write"
        fi
        
        log "Salvando configuração Supervisor para $DOMAIN"
        write_supervisor_file "$CONFIG_CONTENT"
        ;;
    *)
        error "Especifique --read ou --write"
        ;;
esac 