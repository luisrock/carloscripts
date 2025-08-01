#!/bin/bash
# ========================================
# CARLO LOGS SCRIPT
# ========================================
# Visualiza logs de sites Python gerenciados pelo Carlo
# Uso: ./carlo-logs.sh <domain> [--follow] [--lines N] [--type app|nginx|error]

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

# Verificar argumentos
DOMAIN=""
FOLLOW=false
LINES=50
LOG_TYPE="app"

while [[ $# -gt 0 ]]; do
    case $1 in
        --follow|-f)
            FOLLOW=true
            shift
            ;;
        --lines|-n)
            LINES=$2
            shift 2
            ;;
        --type|-t)
            LOG_TYPE=$2
            shift 2
            ;;
        --help|-h)
            echo "Uso: $0 <domain> [opções]"
            echo ""
            echo "Opções:"
            echo "  --follow, -f           Seguir logs em tempo real"
            echo "  --lines N, -n N        Mostrar N linhas (padrão: 50)"
            echo "  --type TYPE, -t TYPE   Tipo de log: app, nginx, error (padrão: app)"
            echo "  --help, -h             Mostrar esta ajuda"
            echo ""
            echo "Exemplos:"
            echo "  $0 meusite.com                    # Últimas 50 linhas do app"
            echo "  $0 meusite.com --follow          # Seguir logs em tempo real"
            echo "  $0 meusite.com --lines 100       # Últimas 100 linhas"
            echo "  $0 meusite.com --type nginx      # Logs do Nginx"
            echo "  $0 meusite.com --type error      # Logs de erro"
            exit 0
            ;;
        *)
            if [ -z "$DOMAIN" ]; then
                DOMAIN=$1
            else
                error "Argumento inválido: $1"
            fi
            shift
            ;;
    esac
done

# Verificar se o domínio foi fornecido
if [ -z "$DOMAIN" ]; then
    error "Uso: $0 <domain> [opções]"
    echo "Execute '$0 --help' para mais informações"
    exit 1
fi

SITE_DIR="/home/carlo/sites/$DOMAIN"

# Verificar se o site existe
if [ ! -d "$SITE_DIR" ]; then
    error "Site $DOMAIN não encontrado"
    echo "Sites disponíveis:"
    ls -1 /home/carlo/sites/ 2>/dev/null || echo "  Nenhum site encontrado"
    exit 1
fi

# Verificar tipo de log
case $LOG_TYPE in
    app|application)
        LOG_FILE="$SITE_DIR/logs/app.log"
        LOG_DESC="Aplicação Python"
        ;;
    nginx|access)
        LOG_FILE="$SITE_DIR/logs/access.log"
        LOG_DESC="Nginx Access"
        ;;
    error|nginx-error)
        LOG_FILE="$SITE_DIR/logs/error.log"
        LOG_DESC="Nginx Error"
        ;;
    supervisor)
        LOG_FILE="supervisorctl"
        LOG_DESC="Supervisor"
        # Para supervisor, verificar se o processo existe
        if ! sudo supervisorctl status "$DOMAIN" >/dev/null 2>&1; then
            error "Processo Supervisor para $DOMAIN não encontrado"
            echo ""
            echo "💡 Possíveis razões:"
            echo "   - O site não foi configurado no Supervisor"
            echo "   - O site foi removido do Supervisor"
            echo "   - Há um problema na configuração"
            echo ""
            echo "🔧 Comandos úteis:"
            echo "   sudo supervisorctl status"
            echo "   sudo supervisorctl reread"
            echo "   sudo supervisorctl update"
            exit 1
        fi
        ;;
    *)
        error "Tipo de log inválido: $LOG_TYPE"
        echo "Tipos válidos: app, nginx, error, supervisor"
        exit 1
        ;;
esac

# Verificar se o arquivo de log existe (exceto para supervisor)
if [ "$LOG_FILE" != "supervisorctl" ] && [ ! -f "$LOG_FILE" ]; then
    error "Arquivo de log não encontrado: $LOG_FILE"
    echo ""
    echo "📁 Arquivos de log disponíveis para $DOMAIN:"
    if [ -d "$SITE_DIR/logs" ]; then
        ls -la "$SITE_DIR/logs/" 2>/dev/null || echo "  Nenhum arquivo de log encontrado"
    fi
    echo ""
    echo "💡 Dicas:"
    echo "  - O log da aplicação só aparece quando o site está rodando"
    echo "  - Execute: sudo supervisorctl start $DOMAIN"
    echo "  - Aguarde alguns segundos e tente novamente"
    exit 1
fi

# Mostrar informações do log
echo -e "${CYAN}📋 LOGS - $DOMAIN${NC}"
echo "=================================="
echo ""
echo "🔍 Informações:"
echo "   Domínio: $DOMAIN"
echo "   Tipo: $LOG_DESC"
if [ "$LOG_FILE" = "supervisorctl" ]; then
    echo "   Fonte: supervisorctl tail"
    echo "   Status: $(sudo supervisorctl status "$DOMAIN" | awk '{print $2}')"
else
    echo "   Arquivo: $LOG_FILE"
    echo "   Tamanho: $(du -h "$LOG_FILE" 2>/dev/null | cut -f1 || echo 'desconhecido')"
fi
echo "   Linhas: $LINES"
if [ "$FOLLOW" = true ]; then
    echo "   Modo: Seguindo em tempo real"
fi
echo ""

# Verificar se o arquivo está vazio (exceto para supervisor)
if [ "$LOG_FILE" != "supervisorctl" ] && [ ! -s "$LOG_FILE" ]; then
    echo -e "${YELLOW}⚠️  Arquivo de log está vazio${NC}"
    echo ""
    echo "💡 Possíveis razões:"
    echo "   - O site não foi iniciado ainda"
    echo "   - O site não gerou logs recentemente"
    echo "   - Há um problema com a aplicação"
    echo ""
    echo "🔧 Comandos úteis:"
    echo "   sudo supervisorctl status $DOMAIN"
    echo "   sudo supervisorctl start $DOMAIN"
    echo "   tail -f $LOG_FILE"
    exit 0
fi

# Mostrar logs
echo -e "${GREEN}📄 Últimas $LINES linhas do log:${NC}"
echo ""

if [ "$LOG_FILE" = "supervisorctl" ]; then
    # Para supervisor, usar supervisorctl tail
    if [ "$FOLLOW" = true ]; then
        echo -e "${PURPLE}🔄 Seguindo logs em tempo real... (Ctrl+C para parar)${NC}"
        echo ""
        sudo supervisorctl tail -f "$DOMAIN"
    else
        sudo supervisorctl tail "$DOMAIN" | tail -n "$LINES"
    fi
else
    # Para arquivos normais, usar tail
    if [ "$FOLLOW" = true ]; then
        echo -e "${PURPLE}🔄 Seguindo logs em tempo real... (Ctrl+C para parar)${NC}"
        echo ""
        tail -f -n "$LINES" "$LOG_FILE"
    else
        tail -n "$LINES" "$LOG_FILE"
    fi
fi

echo ""
echo -e "${CYAN}💡 Comandos úteis:${NC}"
echo "   $0 $DOMAIN --follow          # Seguir logs em tempo real"
echo "   $0 $DOMAIN --lines 100       # Mostrar mais linhas"
echo "   $0 $DOMAIN --type nginx      # Ver logs do Nginx"
echo "   $0 $DOMAIN --type error      # Ver logs de erro"
echo "   sudo supervisorctl restart $DOMAIN  # Reiniciar site" 