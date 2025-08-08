#!/bin/bash
# ========================================
# CARLO ENV EDIT SCRIPT
# ========================================
# Lê, edita e salva arquivos .env para sites Python
# Uso: ./carlo-env-edit.sh <domain> [--read|--write --content <content>]

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

# Determinar localização do arquivo .env (preferir caminho canônico em shared)
if [[ -f "$SITE_DIR/shared/.env" || -d "$SITE_DIR/shared" ]]; then
    ENV_FILE="$SITE_DIR/shared/.env"
    ENV_LOCATION="shared/.env"
elif [[ -d "$SITE_DIR/public" ]]; then
    ENV_FILE="$SITE_DIR/public/.env"
    ENV_LOCATION="public/.env"
else
    ENV_FILE="$SITE_DIR/.env"
    ENV_LOCATION=".env"
fi

# Função para criar backup
create_backup() {
    if [[ ! -f "$ENV_FILE" ]]; then
        return
    fi
    
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_NAME="env_backup_${TIMESTAMP}.env"
    BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"
    
    if cp "$ENV_FILE" "$BACKUP_PATH"; then
        log "Backup criado: $BACKUP_NAME"
        echo "$BACKUP_PATH"
    else
        error "Falha ao criar backup"
    fi
}

# Função para validar conteúdo .env
validate_env_content() {
    local content="$1"
    local line_num=0
    local errors=0
    
    while IFS= read -r line; do
        ((line_num++))
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Ignorar linhas vazias e comentários
        if [[ -z "$line" || "$line" =~ ^# ]]; then
            continue
        fi
        
        # Verificar se tem formato KEY=VALUE
        if [[ ! "$line" =~ = ]]; then
            warning "Linha $line_num: Formato inválido (deve ser KEY=VALUE)"
            ((errors++))
            continue
        fi
        
        # Extrair chave
        key=$(echo "$line" | cut -d'=' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        if [[ -z "$key" ]]; then
            warning "Linha $line_num: Chave vazia"
            ((errors++))
            continue
        fi
        
        # Verificar se a chave tem caracteres válidos
        if [[ ! "$key" =~ ^[A-Za-z0-9_]+$ ]]; then
            warning "Linha $line_num: Chave '$key' contém caracteres inválidos"
            ((errors++))
        fi
    done <<< "$content"
    
    return $errors
}

# Função para ler arquivo .env
read_env_file() {
    if [[ ! -f "$ENV_FILE" ]]; then
        warning "Arquivo .env não encontrado para $DOMAIN"
        log "Localização: $SITE_DIR/$ENV_LOCATION"
        echo "# Arquivo .env para $DOMAIN"
        echo "# Adicione suas variáveis de ambiente aqui"
        echo "# Exemplo:"
        echo "# DATABASE_URL=sqlite:///app.db"
        echo "# SECRET_KEY=your-secret-key"
        echo "# DEBUG=True"
        return
    fi
    
    if cat "$ENV_FILE"; then
        log "Arquivo .env lido com sucesso para $DOMAIN"
        log "Localização: $SITE_DIR/$ENV_LOCATION"
    else
        error "Falha ao ler arquivo .env"
    fi
}

# Função para escrever arquivo .env
write_env_file() {
    local content="$1"
    
    # Verificar se o diretório do site existe
    if [[ ! -d "$SITE_DIR" ]]; then
        error "Diretório do site não encontrado: $SITE_DIR"
    fi
    
    # Criar diretório pai se não existir
    local env_dir=$(dirname "$ENV_FILE")
    if [[ ! -d "$env_dir" ]]; then
        log "Criando diretório: $env_dir"
        mkdir -p "$env_dir"
    fi
    
    # Validar conteúdo
    if ! validate_env_content "$content"; then
        warning "Problemas de validação encontrados no conteúdo .env"
    fi
    
    # Criar backup antes de alterar
    local backup_path=$(create_backup)
    
    # Escrever novo conteúdo (interpretar \n como quebras de linha)
    if echo -e "$content" > "$ENV_FILE"; then
        chmod 644 "$ENV_FILE"
        log "Arquivo .env salvo com sucesso para $DOMAIN"
        log "Localização: $SITE_DIR/$ENV_LOCATION"
        if [[ -n "$backup_path" ]]; then
            log "Backup disponível em: $backup_path"
        fi
        # Atualizar symlink da release atual para garantir carregamento automático
        if [[ -d "$SITE_DIR/current" ]]; then
            ln -sfn "$ENV_FILE" "$SITE_DIR/current/.env"
            log "Symlink atualizado: $SITE_DIR/current/.env -> $ENV_FILE"
        fi
        success "Configuração .env atualizada"
    else
        error "Falha ao salvar arquivo .env"
        
        # Tentar restaurar backup se existir
        if [[ -n "$backup_path" && -f "$backup_path" ]]; then
            if cp "$backup_path" "$ENV_FILE"; then
                warning "Arquivo .env restaurado do backup"
            else
                error "Falha ao restaurar backup"
            fi
        fi
    fi
}

# Executar ação baseada nos argumentos
case "$ACTION" in
    "read")
        log "Lendo configuração .env para $DOMAIN"
        echo "=== CONFIGURAÇÃO ENV PARA $(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]') ==="
        read_env_file
        echo "=== FIM DA CONFIGURAÇÃO ==="
        ;;
    "write")
        if [[ -z "$CONFIG_CONTENT" ]]; then
            error "Conteúdo é obrigatório para operação --write"
        fi
        
        log "Salvando configuração .env para $DOMAIN"
        write_env_file "$CONFIG_CONTENT"
        ;;
    *)
        error "Especifique --read ou --write"
        ;;
esac 