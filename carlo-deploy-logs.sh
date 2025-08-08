#!/bin/bash
# ========================================
# CARLO DEPLOY LOGS SCRIPT
# ========================================
# Gerenciar logs de deploy dos sites
# Uso: ./carlo-deploy-logs.sh <domain> [--list] [--view <log_id>] [--json]

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
    error "Uso: $0 <domain> [--list] [--view <log_id>] [--delete <log_id>] [--json]"
    echo "Exemplo: $0 meusite.com --list"
    echo "         $0 meusite.com --view 20250806_124500"
    echo "         $0 meusite.com --delete 20250806_124500"
    echo "         $0 meusite.com --list --json"
    exit 1
fi

DOMAIN=$1
ACTION=${2:-"--list"}
LOG_ID=$3
JSON_OUTPUT=false

# Verificar se --json foi passado
if [[ "$*" == *"--json"* ]]; then
    JSON_OUTPUT=true
fi

# Configurações
SITE_DIR="/home/carlo/sites/$DOMAIN"
LOGS_DIR="$SITE_DIR/deploy-logs"

# Verificar se o site existe
if [ ! -d "$SITE_DIR" ]; then
    error "Site $DOMAIN não encontrado"
    exit 1
fi

# Criar diretório de logs se não existir
mkdir -p "$LOGS_DIR"

case $ACTION in
    --list)
        if [ "$JSON_OUTPUT" = true ]; then
            # Output JSON
            echo "["
            first=true
            for log_file in $(ls -t "$LOGS_DIR"/*.log 2>/dev/null | head -10); do
                if [ "$first" = true ]; then
                    first=false
                else
                    echo ","
                fi
                
                log_id=$(basename "$log_file" .log)
                status=$(grep -q "SUCESSO.*Deploy.*concluído" "$log_file" && echo "success" || echo "failed")
                timestamp=$(stat -c %Y "$log_file" 2>/dev/null || echo "0")
                duration=$(grep "Duração:" "$log_file" | tail -1 | awk '{print $2}' || echo "0")
                
                echo "  {"
                echo "    \"id\": \"$log_id\","
                echo "    \"status\": \"$status\","
                echo "    \"timestamp\": $timestamp,"
                echo "    \"duration\": \"$duration\","
                echo "    \"file\": \"$log_file\""
                echo "  }"
            done
            echo "]"
        else
            # Output normal
            log "Listando logs de deploy para $DOMAIN:"
            echo ""
            
            if [ ! "$(ls -A "$LOGS_DIR"/*.log 2>/dev/null)" ]; then
                warning "Nenhum log de deploy encontrado"
                exit 0
            fi
            
            printf "%-20s %-10s %-8s %-15s\n" "LOG ID" "STATUS" "DURAÇÃO" "DATA/HORA"
            echo "------------------------------------------------------------"
            
            for log_file in $(ls -t "$LOGS_DIR"/*.log 2>/dev/null | head -10); do
                log_id=$(basename "$log_file" .log)
                status=$(grep -q "SUCESSO.*Deploy.*concluído" "$log_file" && echo "✅ SUCCESS" || echo "❌ FAILED")
                duration=$(grep "Duração:" "$log_file" | tail -1 | awk '{print $2}' || echo "N/A")
                date=$(stat -c %y "$log_file" 2>/dev/null | cut -d' ' -f1,2 | sed 's/ / /' || echo "N/A")
                
                printf "%-20s %-10s %-8s %-15s\n" "$log_id" "$status" "$duration" "$date"
            done
        fi
        ;;
        
    --view)
        if [ -z "$LOG_ID" ]; then
            error "Especifique o ID do log para visualizar"
            echo "Exemplo: $0 $DOMAIN --view 20250806_124500"
            exit 1
        fi
        
        log_file="$LOGS_DIR/${LOG_ID}.log"
        if [ ! -f "$log_file" ]; then
            error "Log $LOG_ID não encontrado"
            exit 1
        fi
        
        log "Visualizando log de deploy: $LOG_ID"
        echo ""
        echo "=== LOG DE DEPLOY: $DOMAIN ==="
        echo "ID: $LOG_ID"
        echo "Arquivo: $log_file"
        echo "=================================="
        echo ""
        cat "$log_file"
        ;;
        
    --delete)
        if [ -z "$LOG_ID" ]; then
            error "Especifique o ID do log para deletar"
            echo "Exemplo: $0 $DOMAIN --delete 20250806_124500"
            exit 1
        fi
        
        log_file="$LOGS_DIR/${LOG_ID}.log"
        if [ ! -f "$log_file" ]; then
            error "Log $LOG_ID não encontrado"
            exit 1
        fi
        
        log "Deletando log de deploy: $LOG_ID"
        rm -f "$log_file"
        success "Log $LOG_ID deletado com sucesso"
        ;;
        
    *)
        error "Ação inválida: $ACTION"
        echo "Ações válidas: --list, --view, --delete"
        exit 1
        ;;
esac 