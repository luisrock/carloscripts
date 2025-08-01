#!/bin/bash
# ========================================
# CARLO GUNICORN EDIT SCRIPT
# ========================================
# Lê, edita e salva configurações Gunicorn para sites Python
# Uso: ./carlo-gunicorn-edit.sh <domain> [--read|--write --content <content>]

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
GUNICORN_CONF="$SITE_DIR/gunicorn.conf"

# Função para criar backup
create_backup() {
    if [[ ! -f "$GUNICORN_CONF" ]]; then
        return
    fi
    
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_NAME="gunicorn_backup_${TIMESTAMP}.conf"
    BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"
    
    if cp "$GUNICORN_CONF" "$BACKUP_PATH"; then
        log "Backup criado: $BACKUP_NAME"
        echo "$BACKUP_PATH"
    else
        error "Falha ao criar backup"
    fi
}

# Função para validar conteúdo Gunicorn
validate_gunicorn_content() {
    local content="$1"
    local errors=0
    
    # Verificar se tem configurações básicas
    if ! echo "$content" | grep -q "bind ="; then
        warning "Configuração 'bind' não encontrada"
        ((errors++))
    fi
    
    if ! echo "$content" | grep -q "workers ="; then
        warning "Configuração 'workers' não encontrada"
        ((errors++))
    fi
    
    return $errors
}

# Função para ler arquivo Gunicorn
read_gunicorn_file() {
    if [[ ! -f "$GUNICORN_CONF" ]]; then
        warning "Arquivo gunicorn.conf não encontrado para $DOMAIN"
        log "Localização: $SITE_DIR/gunicorn.conf"
        echo "# Configuração Gunicorn para $DOMAIN"
        echo "# Adicione suas configurações do Gunicorn aqui"
        echo "# Exemplo:"
        echo "# bind = \"127.0.0.1:5000\""
        echo "# workers = 3"
        echo "# worker_class = \"sync\""
        return
    fi
    
    if cat "$GUNICORN_CONF"; then
        log "Arquivo gunicorn.conf lido com sucesso para $DOMAIN"
        log "Localização: $SITE_DIR/gunicorn.conf"
    else
        error "Falha ao ler arquivo gunicorn.conf"
    fi
}

# Função para escrever arquivo Gunicorn
write_gunicorn_file() {
    local content="$1"
    
    # Verificar se o diretório do site existe
    if [[ ! -d "$SITE_DIR" ]]; then
        error "Diretório do site não encontrado: $SITE_DIR"
    fi
    
    # Validar conteúdo
    if ! validate_gunicorn_content "$content"; then
        warning "Problemas de validação encontrados no conteúdo Gunicorn"
    fi
    
    # Criar backup antes de alterar
    local backup_path=$(create_backup)
    
    # Escrever novo conteúdo (interpretar \n como quebras de linha)
    if echo -e "$content" > "$GUNICORN_CONF"; then
        chmod 644 "$GUNICORN_CONF"
        log "Arquivo gunicorn.conf salvo com sucesso para $DOMAIN"
        log "Localização: $SITE_DIR/gunicorn.conf"
        if [[ -n "$backup_path" ]]; then
            log "Backup disponível em: $backup_path"
        fi
        success "Configuração Gunicorn atualizada"
    else
        error "Falha ao salvar arquivo gunicorn.conf"
        
        # Tentar restaurar backup se existir
        if [[ -n "$backup_path" && -f "$backup_path" ]]; then
            if cp "$backup_path" "$GUNICORN_CONF"; then
                warning "Arquivo gunicorn.conf restaurado do backup"
            else
                error "Falha ao restaurar backup"
            fi
        fi
    fi
}

# Executar ação baseada nos argumentos
case "$ACTION" in
    "read")
        log "Lendo configuração Gunicorn para $DOMAIN"
        echo "=== CONFIGURAÇÃO GUNICORN PARA $(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]') ==="
        read_gunicorn_file
        echo "=== FIM DA CONFIGURAÇÃO ==="
        ;;
    "write")
        if [[ -z "$CONFIG_CONTENT" ]]; then
            error "Conteúdo é obrigatório para operação --write"
        fi
        
        log "Salvando configuração Gunicorn para $DOMAIN"
        write_gunicorn_file "$CONFIG_CONTENT"
        ;;
    *)
        error "Especifique --read ou --write"
        ;;
esac 