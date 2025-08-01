#!/bin/bash
# ========================================
# CARLO APP EDIT SCRIPT
# ========================================
# Lê, edita e salva aplicações Python (app.py) para sites
# Uso: ./carlo-app-edit.sh <domain> [--read|--write --content <content>]

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
APP_FILE="$SITE_DIR/public/app.py"

# Verificar se o site existe
if [[ ! -d "$SITE_DIR" ]]; then
    error "Site $DOMAIN não encontrado"
    echo "Execute: ./carlo-create-site.sh $DOMAIN <port> para criar o site"
    exit 1
fi

# Função para criar backup
create_backup() {
    if [[ ! -f "$APP_FILE" ]]; then
        return
    fi
    
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_NAME="app_backup_${TIMESTAMP}.py"
    BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"
    
    if cp "$APP_FILE" "$BACKUP_PATH"; then
        log "Backup criado: $BACKUP_NAME"
        echo "$BACKUP_PATH"
    else
        error "Falha ao criar backup"
    fi
}

# Função para validar conteúdo Python
validate_python_content() {
    local content="$1"
    local temp_file="/tmp/app_validate_$DOMAIN.py"
    local errors=0
    
    # Criar arquivo temporário para validação
    echo "$content" > "$temp_file"
    
    # Verificar sintaxe Python básica
    if ! python3 -m py_compile "$temp_file" 2>/dev/null; then
        warning "Erro de sintaxe Python detectado"
        python3 -m py_compile "$temp_file" 2>&1 | head -5
        ((errors++))
    fi
    
    # Verificar se tem imports básicos
    if ! echo "$content" | grep -q "from flask\|import flask\|from fastapi\|import fastapi\|from django\|import django"; then
        warning "Nenhum framework Python detectado (Flask, FastAPI, Django)"
        ((errors++))
    fi
    
    # Verificar se tem função main ou app
    if ! echo "$content" | grep -q "if __name__\|app.run\|uvicorn.run"; then
        warning "Ponto de entrada não encontrado (if __name__ == '__main__' ou app.run)"
        ((errors++))
    fi
    
    # Limpar arquivo temporário
    rm -f "$temp_file"
    
    return $errors
}

# Função para ler arquivo App
read_app_file() {
    if [[ ! -f "$APP_FILE" ]]; then
        warning "Arquivo app.py não encontrado para $DOMAIN"
        log "Localização: $SITE_DIR/public/app.py"
        echo "# Aplicação Python para $DOMAIN"
        echo "# Adicione sua aplicação Flask/FastAPI/Django aqui"
        echo "# Exemplo Flask:"
        echo "from flask import Flask, render_template"
        echo "import os"
        echo ""
        echo "app = Flask(__name__)"
        echo ""
        echo "@app.route('/')"
        echo "def hello():"
        echo "    return 'Hello, World!'"
        echo ""
        echo "if __name__ == '__main__':"
        echo "    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 5000)), debug=False)"
        return
    fi
    
    if cat "$APP_FILE"; then
        log "Arquivo app.py lido com sucesso para $DOMAIN"
        log "Localização: $SITE_DIR/public/app.py"
    else
        error "Falha ao ler arquivo app.py"
    fi
}

# Função para escrever arquivo App
write_app_file() {
    local content="$1"
    
    # Verificar se o diretório do site existe
    if [[ ! -d "$SITE_DIR" ]]; then
        error "Diretório do site não encontrado: $SITE_DIR"
    fi
    
    # Criar diretório public se não existir
    if [[ ! -d "$SITE_DIR/public" ]]; then
        log "Criando diretório public"
        mkdir -p "$SITE_DIR/public"
    fi
    
    # Validar conteúdo
    if ! validate_python_content "$content"; then
        warning "Problemas de validação encontrados no conteúdo Python"
    fi
    
    # Criar backup antes de alterar
    local backup_path=$(create_backup)
    
    # Escrever novo conteúdo (interpretar \n como quebras de linha)
    if echo -e "$content" > "$APP_FILE"; then
        chmod 644 "$APP_FILE"
        log "Arquivo app.py salvo com sucesso para $DOMAIN"
        log "Localização: $SITE_DIR/public/app.py"
        if [[ -n "$backup_path" ]]; then
            log "Backup disponível em: $backup_path"
        fi
        
        # Testar se a aplicação inicia corretamente
        log "Testando aplicação..."
        cd "$SITE_DIR/public"
        if timeout 10s python3 -c "import app; print('App OK')" 2>/dev/null; then
            log "Aplicação testada com sucesso"
            success "Aplicação Python atualizada"
        else
            warning "Falha ao testar aplicação (verifique logs)"
            success "Aplicação Python salva"
        fi
    else
        error "Falha ao salvar arquivo app.py"
        
        # Tentar restaurar backup se existir
        if [[ -n "$backup_path" && -f "$backup_path" ]]; then
            if cp "$backup_path" "$APP_FILE"; then
                warning "Arquivo app.py restaurado do backup"
            else
                error "Falha ao restaurar backup"
            fi
        fi
    fi
}

# Executar ação baseada nos argumentos
case "$ACTION" in
    "read")
        log "Lendo aplicação Python para $DOMAIN"
        echo "=== CONFIGURAÇÃO APP PARA $(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]') ==="
        read_app_file
        echo "=== FIM DA CONFIGURAÇÃO ==="
        ;;
    "write")
        if [[ -z "$CONFIG_CONTENT" ]]; then
            error "Conteúdo é obrigatório para operação --write"
        fi
        
        log "Salvando aplicação Python para $DOMAIN"
        write_app_file "$CONFIG_CONTENT"
        ;;
    *)
        error "Especifique --read ou --write"
        ;;
esac 