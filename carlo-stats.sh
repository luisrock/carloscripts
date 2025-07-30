#!/bin/bash
# ========================================
# CARLO STATS SCRIPT
# ========================================
# Mostra estatísticas do sistema Carlo
# Uso: ./carlo-stats.sh [--json] [--detailed]

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Verificar argumentos
JSON_OUTPUT=false
DETAILED=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --detailed)
            DETAILED=true
            shift
            ;;
        *)
            echo "Uso: $0 [--json] [--detailed]"
            exit 1
            ;;
    esac
done

# Função para obter informações do sistema
get_system_info() {
    # CPU
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    cpu_cores=$(nproc)
    cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    
    # Memória
    mem_total=$(free -m | awk 'NR==2{printf "%.1f", $2/1024}')
    mem_used=$(free -m | awk 'NR==2{printf "%.1f", $3/1024}')
    mem_free=$(free -m | awk 'NR==2{printf "%.1f", $4/1024}')
    mem_usage=$(free | awk 'NR==2{printf "%.1f", $3/$2*100}')
    
    # Disco
    disk_total=$(df -h / | awk 'NR==2{print $2}')
    disk_used=$(df -h / | awk 'NR==2{print $3}')
    disk_free=$(df -h / | awk 'NR==2{print $4}')
    disk_usage=$(df / | awk 'NR==2{print $5}' | cut -d'%' -f1)
    
    # Swap
    swap_total=$(free -m | awk 'NR==3{printf "%.1f", $2/1024}')
    swap_used=$(free -m | awk 'NR==3{printf "%.1f", $3/1024}')
    swap_free=$(free -m | awk 'NR==3{printf "%.1f", $4/1024}')
    
    # Uptime
    uptime=$(uptime -p | sed 's/up //')
    
    # Load average
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    
    echo "{\"cpu\":{\"usage\":$cpu_usage,\"cores\":$cpu_cores,\"model\":\"$cpu_model\"},\"memory\":{\"total\":$mem_total,\"used\":$mem_used,\"free\":$mem_free,\"usage\":$mem_usage},\"disk\":{\"total\":\"$disk_total\",\"used\":\"$disk_used\",\"free\":\"$disk_free\",\"usage\":$disk_usage},\"swap\":{\"total\":$swap_total,\"used\":$swap_used,\"free\":$swap_free},\"uptime\":\"$uptime\",\"load_average\":\"$load_avg\"}"
}

# Função para obter informações dos sites
get_sites_info() {
    sites_running=0
    sites_stopped=0
    sites_total=0
    
    if [ -d "/home/carlo/sites" ]; then
        for site_dir in /home/carlo/sites/*/; do
            if [ -d "$site_dir" ]; then
                domain=$(basename "$site_dir")
                ((sites_total++))
                
                if sudo supervisorctl status "$domain" 2>/dev/null | grep -q "RUNNING"; then
                    ((sites_running++))
                else
                    ((sites_stopped++))
                fi
            fi
        done
    fi
    
    echo "{\"total\":$sites_total,\"running\":$sites_running,\"stopped\":$sites_stopped}"
}

# Função para obter informações dos serviços
get_services_info() {
    # Nginx
    nginx_status="stopped"
    if systemctl is-active --quiet nginx; then
        nginx_status="running"
    fi
    
    # MySQL
    mysql_status="stopped"
    if systemctl is-active --quiet mysql; then
        mysql_status="running"
    fi
    
    # Supervisor
    supervisor_status="stopped"
    if systemctl is-active --quiet supervisor; then
        supervisor_status="running"
    fi
    
    echo "{\"nginx\":\"$nginx_status\",\"mysql\":\"$mysql_status\",\"supervisor\":\"$supervisor_status\"}"
}

# Função para obter informações detalhadas
get_detailed_info() {
    # Processos Python
    python_processes=$(ps aux | grep python | grep -v grep | wc -l)
    
    # Portas em uso
    ports_in_use=$(netstat -tuln | grep LISTEN | wc -l)
    
    # Arquivos de log
    log_files=$(find /home/carlo/sites -name "*.log" 2>/dev/null | wc -l)
    
    # Tamanho total dos sites
    sites_size=$(du -sh /home/carlo/sites 2>/dev/null | cut -f1 || echo "0")
    
    # Últimos backups
    backup_count=$(find /home/carlo/backups -name "*.tar.gz" 2>/dev/null | wc -l)
    
    echo "{\"python_processes\":$python_processes,\"ports_in_use\":$ports_in_use,\"log_files\":$log_files,\"sites_size\":\"$sites_size\",\"backup_count\":$backup_count}"
}

# Coletar todas as informações
system_info=$(get_system_info)
sites_info=$(get_sites_info)
services_info=$(get_services_info)

if [ "$DETAILED" = true ]; then
    detailed_info=$(get_detailed_info)
fi

# Output
if [ "$JSON_OUTPUT" = true ]; then
    # Output JSON
    if [ "$DETAILED" = true ]; then
        echo "{\"system\":$system_info,\"sites\":$sites_info,\"services\":$services_info,\"detailed\":$detailed_info,\"timestamp\":\"$(date -Iseconds)\"}"
    else
        echo "{\"system\":$system_info,\"sites\":$sites_info,\"services\":$services_info,\"timestamp\":\"$(date -Iseconds)\"}"
    fi
else
    # Output formatado
    echo -e "${CYAN}📊 ESTATÍSTICAS DO SISTEMA CARLO${NC}"
    echo "=========================================="
    echo ""
    
    # Informações do sistema
    cpu_usage=$(echo "$system_info" | jq -r '.cpu.usage')
    cpu_cores=$(echo "$system_info" | jq -r '.cpu.cores')
    mem_usage=$(echo "$system_info" | jq -r '.memory.usage')
    mem_total=$(echo "$system_info" | jq -r '.memory.total')
    mem_used=$(echo "$system_info" | jq -r '.memory.used')
    disk_usage=$(echo "$system_info" | jq -r '.disk.usage')
    disk_total=$(echo "$system_info" | jq -r '.disk.total')
    disk_used=$(echo "$system_info" | jq -r '.disk.used')
    uptime=$(echo "$system_info" | jq -r '.uptime')
    load_avg=$(echo "$system_info" | jq -r '.load_average')
    
    echo -e "${BLUE}🖥️  SISTEMA${NC}"
    echo "   CPU: ${cpu_usage}% (${cpu_cores} cores)"
    echo "   Memória: ${mem_usage}% (${mem_used}GB / ${mem_total}GB)"
    echo "   Disco: ${disk_usage}% (${disk_used} / ${disk_total})"
    echo "   Uptime: $uptime"
    echo "   Load: $load_avg"
    echo ""
    
    # Informações dos sites
    sites_total=$(echo "$sites_info" | jq -r '.total')
    sites_running=$(echo "$sites_info" | jq -r '.running')
    sites_stopped=$(echo "$sites_info" | jq -r '.stopped')
    
    echo -e "${GREEN}🐍 SITES PYTHON${NC}"
    echo "   Total: $sites_total"
    echo "   Rodando: $sites_running"
    echo "   Parados: $sites_stopped"
    echo ""
    
    # Informações dos serviços
    nginx_status=$(echo "$services_info" | jq -r '.nginx')
    mysql_status=$(echo "$services_info" | jq -r '.mysql')
    supervisor_status=$(echo "$services_info" | jq -r '.supervisor')
    
    echo -e "${PURPLE}🔧 SERVIÇOS${NC}"
    echo "   Nginx: $nginx_status"
    echo "   MySQL: $mysql_status"
    echo "   Supervisor: $supervisor_status"
    echo ""
    
    if [ "$DETAILED" = true ]; then
        # Informações detalhadas
        python_processes=$(echo "$detailed_info" | jq -r '.python_processes')
        ports_in_use=$(echo "$detailed_info" | jq -r '.ports_in_use')
        log_files=$(echo "$detailed_info" | jq -r '.log_files')
        sites_size=$(echo "$detailed_info" | jq -r '.sites_size')
        backup_count=$(echo "$detailed_info" | jq -r '.backup_count')
        
        echo -e "${YELLOW}📈 DETALHES${NC}"
        echo "   Processos Python: $python_processes"
        echo "   Portas em uso: $ports_in_use"
        echo "   Arquivos de log: $log_files"
        echo "   Tamanho dos sites: $sites_size"
        echo "   Backups: $backup_count"
        echo ""
    fi
    
    # Status geral
    echo -e "${CYAN}📋 STATUS GERAL${NC}"
    if (( $(echo "$cpu_usage > 80" | bc -l) )); then
        echo -e "   CPU: ${RED}ALTO${NC} (>80%)"
    elif (( $(echo "$cpu_usage > 60" | bc -l) )); then
        echo -e "   CPU: ${YELLOW}MÉDIO${NC} (60-80%)"
    else
        echo -e "   CPU: ${GREEN}NORMAL${NC} (<60%)"
    fi
    
    if (( $(echo "$mem_usage > 80" | bc -l) )); then
        echo -e "   Memória: ${RED}ALTA${NC} (>80%)"
    elif (( $(echo "$mem_usage > 60" | bc -l) )); then
        echo -e "   Memória: ${YELLOW}MÉDIA${NC} (60-80%)"
    else
        echo -e "   Memória: ${GREEN}NORMAL${NC} (<60%)"
    fi
    
    if (( $(echo "$disk_usage > 80" | bc -l) )); then
        echo -e "   Disco: ${RED}ALTO${NC} (>80%)"
    elif (( $(echo "$disk_usage > 60" | bc -l) )); then
        echo -e "   Disco: ${YELLOW}MÉDIO${NC} (60-80%)"
    else
        echo -e "   Disco: ${GREEN}NORMAL${NC} (<60%)"
    fi
    
    echo ""
    echo -e "${CYAN}💡 Comandos úteis:${NC}"
    echo "   ./carlo-list-sites.sh          # Listar sites"
    echo "   ./carlo-logs.sh <domain>       # Ver logs"
    echo "   sudo supervisorctl status       # Status dos processos"
    echo "   htop                           # Monitor de processos"
fi 