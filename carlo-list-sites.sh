#!/bin/bash
# ========================================
# CARLO LIST SITES SCRIPT
# ========================================
# Lista todos os sites Python gerenciados pelo Carlo
# Uso: ./carlo-list-sites.sh [--json] [--status]

# Remover set -e para evitar paradas inesperadas
# set -e

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

# Verificar argumentos
JSON_OUTPUT=false
SHOW_STATUS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --status)
            SHOW_STATUS=true
            shift
            ;;
        *)
            echo "Uso: $0 [--json] [--status]"
            exit 1
            ;;
    esac
done

# Verificar se o diretório Carlo existe
if [ ! -d "/home/carlo/sites" ]; then
    if [ "$JSON_OUTPUT" = true ]; then
        echo '{"sites": [], "total": 0, "message": "Nenhum site encontrado"}'
    else
        echo -e "${YELLOW}Nenhum site encontrado no sistema Carlo${NC}"
        echo "Execute: ./carlo-create-site.sh <domain> <port> para criar um site"
    fi
    exit 0
fi

# Função para obter status do supervisor
get_supervisor_status() {
    local domain=$1
    if sudo supervisorctl status "$domain" 2>/dev/null | grep -q "RUNNING"; then
        echo "running"
    elif sudo supervisorctl status "$domain" 2>/dev/null | grep -q "STOPPED"; then
        echo "stopped"
    else
        echo "unknown"
    fi
}

# Função para obter informações do site
get_site_info() {
    local site_dir=$1
    local domain=$(basename "$site_dir")
    
    if [ -f "$site_dir/status.json" ]; then
        # Verificar se o JSON é válido
        if jq empty "$site_dir/status.json" 2>/dev/null; then
            cat "$site_dir/status.json"
        else
            # JSON inválido, criar novo
            cat > "$site_dir/status.json" << EOF
{
    "domain": "$domain",
    "port": 5000,
    "framework": "unknown",
    "python_version": "3.12",
    "status": "unknown",
    "created_at": "$(date -Iseconds)",
    "last_started": null,
    "last_stopped": null
}
EOF
            cat "$site_dir/status.json"
        fi
    else
        # Criar status.json básico se não existir
        cat > "$site_dir/status.json" << EOF
{
    "domain": "$domain",
    "port": 5000,
    "framework": "unknown",
    "python_version": "3.12",
    "status": "unknown",
    "created_at": "$(date -Iseconds)",
    "last_started": null,
    "last_stopped": null
}
EOF
        cat "$site_dir/status.json"
    fi
}

# Função para obter estatísticas do site
get_site_stats() {
    local site_dir=$1
    local domain=$(basename "$site_dir")
    
    # Tamanho do diretório
    local size=$(du -sh "$site_dir" 2>/dev/null | cut -f1 || echo "0")
    
    # Última modificação
    local last_modified=$(stat -c %y "$site_dir" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
    
    # Status do supervisor
    local supervisor_status=$(get_supervisor_status "$domain")
    
    # Verificar se porta está em uso
    local port="5000"
    if [ -f "$site_dir/status.json" ]; then
        port=$(jq -r '.port // 5000' "$site_dir/status.json" 2>/dev/null || echo "5000")
    fi
    local port_status="unknown"
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        port_status="in_use"
    else
        port_status="free"
    fi
    
    echo "{\"size\": \"$size\", \"last_modified\": \"$last_modified\", \"supervisor_status\": \"$supervisor_status\", \"port_status\": \"$port_status\"}"
}

# Listar sites
sites=()
total=0

for site_dir in /home/carlo/sites/*/; do
    if [ -d "$site_dir" ]; then
        domain=$(basename "$site_dir")
        
        # Obter informações básicas com tratamento de erro
        site_info=$(get_site_info "$site_dir" 2>/dev/null || echo "{}")
        
        # Verificar se site_info não está vazio
        if [ -n "$site_info" ] && [ "$site_info" != "{}" ]; then
            # Obter estatísticas se solicitado
            if [ "$SHOW_STATUS" = true ]; then
                stats=$(get_site_stats "$site_dir" 2>/dev/null || echo "{}")
                # Combinar informações de forma mais robusta
                if [ -n "$stats" ] && [ "$stats" != "{}" ]; then
                    site_info=$(echo "$site_info" | jq -s '.[0] + .[1]' <(echo "$site_info") <(echo "$stats") 2>/dev/null || echo "$site_info")
                fi
            fi
            
            sites+=("$site_info")
            ((total++))
        fi
    fi
done

# Output
if [ "$JSON_OUTPUT" = true ]; then
    # Output JSON
    if [ "$SHOW_STATUS" = true ]; then
        # Construir JSON de forma mais robusta
        if [ $total -eq 0 ]; then
            echo "{\"sites\": [], \"total\": 0, \"timestamp\": \"$(date -Iseconds)\"}"
        else
            # Criar array JSON manualmente
            json_sites=""
            for i in "${!sites[@]}"; do
                if [ $i -gt 0 ]; then
                    json_sites="$json_sites,"
                fi
                json_sites="$json_sites${sites[$i]}"
            done
            echo "{\"sites\": [$json_sites], \"total\": $total, \"timestamp\": \"$(date -Iseconds)\"}"
        fi
    else
        # Construir JSON de forma mais robusta
        if [ $total -eq 0 ]; then
            echo "{\"sites\": [], \"total\": 0, \"timestamp\": \"$(date -Iseconds)\"}"
        else
            # Criar array JSON manualmente
            json_sites=""
            for i in "${!sites[@]}"; do
                if [ $i -gt 0 ]; then
                    json_sites="$json_sites,"
                fi
                json_sites="$json_sites${sites[$i]}"
            done
            echo "{\"sites\": [$json_sites], \"total\": $total, \"timestamp\": \"$(date -Iseconds)\"}"
        fi
    fi
else
    # Output formatado
    echo -e "${CYAN}🐍 SITES PYTHON - CARLO DEPLOY${NC}"
    echo "=================================="
    echo ""
    
    if [ $total -eq 0 ]; then
        echo -e "${YELLOW}Nenhum site encontrado${NC}"
        echo ""
        echo "Para criar um site:"
        echo "  ./carlo-create-site.sh <domain> <port> [python_version] [framework]"
        echo ""
        echo "Exemplo:"
        echo "  ./carlo-create-site.sh meusite.com 5000 3.12 flask"
    else
        echo -e "${GREEN}Encontrados $total site(s):${NC}"
        echo ""
        
        # Cabeçalho da tabela
        printf "%-25s %-8s %-10s %-12s %-15s\n" "DOMÍNIO" "PORTA" "FRAMEWORK" "STATUS" "CRIADO EM"
        echo "--------------------------------------------------------------------------------"
        
        for site_info in "${sites[@]}"; do
            domain=$(echo "$site_info" | jq -r '.domain // "unknown"')
            port=$(echo "$site_info" | jq -r '.port // "unknown"')
            framework=$(echo "$site_info" | jq -r '.framework // "unknown"')
            status=$(echo "$site_info" | jq -r '.status // "unknown"')
            created_at=$(echo "$site_info" | jq -r '.created_at // "unknown"')
            
            # Formatar data
            if [ "$created_at" != "unknown" ]; then
                created_at=$(echo "$created_at" | cut -d'T' -f1)
            fi
            
            # Colorir status
            case $status in
                "running")
                    status_colored="${GREEN}● running${NC}"
                    ;;
                "stopped")
                    status_colored="${RED}● stopped${NC}"
                    ;;
                "created")
                    status_colored="${YELLOW}● created${NC}"
                    ;;
                *)
                    status_colored="${PURPLE}● $status${NC}"
                    ;;
            esac
            
            printf "%-25s %-8s %-10s %-12s %-15s\n" "$domain" "$port" "$framework" "$status_colored" "$created_at"
        done
        
        echo ""
        echo -e "${CYAN}Comandos úteis:${NC}"
        echo "  ./carlo-start-site.sh <domain>    # Iniciar site"
        echo "  ./carlo-stop-site.sh <domain>     # Parar site"
        echo "  ./carlo-delete-site.sh <domain>   # Deletar site"
        echo "  ./carlo-logs.sh <domain>          # Ver logs"
        
        if [ "$SHOW_STATUS" = true ]; then
            echo ""
            echo -e "${CYAN}Estatísticas detalhadas:${NC}"
            for site_info in "${sites[@]}"; do
                domain=$(echo "$site_info" | jq -r '.domain')
                size=$(echo "$site_info" | jq -r '.size // "unknown"')
                supervisor_status=$(echo "$site_info" | jq -r '.supervisor_status // "unknown"')
                port_status=$(echo "$site_info" | jq -r '.port_status // "unknown"')
                
                echo -e "  ${BLUE}$domain:${NC}"
                echo -e "    Tamanho: $size"
                echo -e "    Supervisor: $supervisor_status"
                echo -e "    Porta: $port_status"
                echo ""
            done
        fi
    fi
fi 