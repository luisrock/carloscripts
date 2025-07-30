#!/bin/bash
# ========================================
# CARLO VIEW SITE SCRIPT
# ========================================
# Mostra detalhes completos de um site Python gerenciado pelo Carlo
# Uso: ./carlo-view-site.sh <domain> [--json] [--html]

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
JSON_OUTPUT=false
HTML_OUTPUT=false
DOMAIN=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --html)
            HTML_OUTPUT=true
            shift
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
    error "Uso: $0 <domain> [--json] [--html]"
    echo "Exemplo: $0 meusite.com"
    echo "         $0 meusite.com --json"
    echo "         $0 meusite.com --html"
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

# Função para obter informações básicas do site
get_basic_info() {
    local domain=$1
    local site_dir="/home/carlo/sites/$domain"
    
    # Informações do status.json
    local status_file="$site_dir/status.json"
    if [ -f "$status_file" ]; then
        local port=$(jq -r '.port // 5000' "$status_file" 2>/dev/null || echo "5000")
        local framework=$(jq -r '.framework // "unknown"' "$status_file" 2>/dev/null || echo "unknown")
        local python_version=$(jq -r '.python_version // "3.12"' "$status_file" 2>/dev/null || echo "3.12")
        local status=$(jq -r '.status // "unknown"' "$status_file" 2>/dev/null || echo "unknown")
        local created_at=$(jq -r '.created_at // "unknown"' "$status_file" 2>/dev/null || echo "unknown")
        local last_started=$(jq -r '.last_started // null' "$status_file" 2>/dev/null || echo "null")
        local last_stopped=$(jq -r '.last_stopped // null' "$status_file" 2>/dev/null || echo "null")
        
        jq -n \
            --arg domain "$domain" \
            --arg port "$port" \
            --arg framework "$framework" \
            --arg python_version "$python_version" \
            --arg status "$status" \
            --arg created_at "$created_at" \
            --arg last_started "$last_started" \
            --arg last_stopped "$last_stopped" \
            '{
                domain: $domain,
                port: ($port | tonumber),
                framework: $framework,
                python_version: $python_version,
                status: $status,
                created_at: $created_at,
                last_started: $last_started,
                last_stopped: $last_stopped
            }'
    else
        jq -n \
            --arg domain "$domain" \
            '{
                domain: $domain,
                port: 5000,
                framework: "unknown",
                python_version: "3.12",
                status: "unknown",
                created_at: "unknown",
                last_started: null,
                last_stopped: null
            }'
    fi
}

# Função para obter status do supervisor
get_supervisor_status() {
    local domain=$1
    local supervisor_status=$(sudo supervisorctl status "$domain" 2>/dev/null || echo "UNKNOWN")
    local pid=$(echo "$supervisor_status" | awk '{print $4}' | cut -d',' -f1)
    local uptime=$(echo "$supervisor_status" | awk '{print $6}')
    
    # Usar jq para criar JSON de forma segura
    if echo "$supervisor_status" | grep -q "RUNNING"; then
        local status="running"
        local status_code=1
    elif echo "$supervisor_status" | grep -q "STOPPED"; then
        local status="stopped"
        local status_code=0
    else
        local status="unknown"
        local status_code=-1
    fi
    
    jq -n \
        --arg status "$status" \
        --arg status_code "$status_code" \
        --arg pid "$pid" \
        --arg uptime "$uptime" \
        --arg supervisor_status "$supervisor_status" \
        '{
            status: $status,
            status_code: ($status_code | tonumber),
            pid: $pid,
            uptime: $uptime,
            supervisor_status: $supervisor_status
        }'
}

# Função para obter informações de porta
get_port_info() {
    local domain=$1
    local port=$(jq -r '.port // 5000' "$SITE_DIR/status.json" 2>/dev/null || echo "5000")
    
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        local port_status="in_use"
        local port_process=$(netstat -tulnp 2>/dev/null | grep ":$port " | awk '{print $7}' | cut -d'/' -f1)
    else
        local port_status="free"
        local port_process=""
    fi
    
    echo "{\"port\":$port,\"status\":\"$port_status\",\"process\":\"$port_process\"}"
}

# Função para obter informações de deploy
get_deploy_info() {
    local domain=$1
    local site_dir="/home/carlo/sites/$domain"
    
    if [ -f "$site_dir/config/github.conf" ]; then
        source "$site_dir/config/github.conf"
        local github_repo="$GITHUB_REPO"
        local github_branch="$GITHUB_BRANCH"
        local webhook_url="$WEBHOOK_URL"
    else
        local github_repo=""
        local github_branch=""
        local webhook_url=""
    fi
    
    # Informações de deploy do status.json
    local last_deploy=$(jq -r '.last_deploy // null' "$site_dir/status.json" 2>/dev/null || echo "null")
    local deploy_timestamp=$(jq -r '.deploy_timestamp // null' "$site_dir/status.json" 2>/dev/null || echo "null")
    
    # Releases disponíveis
    local releases=()
    if [ -d "$site_dir/releases" ]; then
        releases=($(ls -t "$site_dir/releases" 2>/dev/null))
    fi
    
    local current_release=""
    if [ -L "$site_dir/current" ]; then
        current_release=$(readlink "$site_dir/current" | xargs basename 2>/dev/null || echo "")
    fi
    
    echo "{\"github_repo\":\"$github_repo\",\"github_branch\":\"$github_branch\",\"webhook_url\":\"$webhook_url\",\"last_deploy\":\"$last_deploy\",\"deploy_timestamp\":\"$deploy_timestamp\",\"releases\":$(printf '%s\n' "${releases[@]}" | jq -R . | jq -s .),\"current_release\":\"$current_release\",\"releases_count\":${#releases[@]}}"
}

# Função para obter informações SSL
get_ssl_info() {
    local domain=$1
    local cert_file="/home/carlo/ssl/$domain/live/cert.pem"
    
    if [ -f "$cert_file" ]; then
        local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
        local start_date=$(openssl x509 -in "$cert_file" -noout -startdate 2>/dev/null | cut -d= -f2)
        local issuer=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null | sed 's/issuer=//')
        
        # Calcular dias até expirar
        local current_timestamp=$(date +%s)
        local expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null)
        local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
        
        # Determinar status
        local ssl_status="valid"
        if [ "$days_until_expiry" -lt 0 ]; then
            ssl_status="expired"
        elif [ "$days_until_expiry" -lt 7 ]; then
            ssl_status="critical"
        elif [ "$days_until_expiry" -lt 30 ]; then
            ssl_status="warning"
        fi
        
        echo "{\"enabled\":true,\"expiry_date\":\"$expiry_date\",\"start_date\":\"$start_date\",\"issuer\":\"$issuer\",\"days_until_expiry\":$days_until_expiry,\"status\":\"$ssl_status\"}"
    else
        echo "{\"enabled\":false,\"expiry_date\":null,\"start_date\":null,\"issuer\":null,\"days_until_expiry\":null,\"status\":\"not_installed\"}"
    fi
}

# Função para obter informações de sistema
get_system_info() {
    local domain=$1
    local site_dir="/home/carlo/sites/$domain"
    
    # Tamanho do diretório
    local dir_size=$(du -sh "$site_dir" 2>/dev/null | cut -f1 || echo "0")
    
    # Tamanho dos logs
    local logs_size=$(du -sh "$site_dir/logs" 2>/dev/null | cut -f1 || echo "0")
    
    # Última modificação
    local last_modified=$(stat -c %y "$site_dir" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
    
    # Permissões
    local permissions=$(stat -c %a "$site_dir" 2>/dev/null || echo "unknown")
    
    # Uso de CPU e memória do processo
    local cpu_usage="0"
    local mem_usage="0"
    local pid=$(sudo supervisorctl status "$domain" 2>/dev/null | awk '{print $4}' | cut -d',' -f1)
    
    if [ -n "$pid" ] && [ "$pid" != "N/A" ]; then
        cpu_usage=$(ps -p "$pid" -o %cpu= 2>/dev/null || echo "0")
        mem_usage=$(ps -p "$pid" -o %mem= 2>/dev/null || echo "0")
    fi
    
    echo "{\"dir_size\":\"$dir_size\",\"logs_size\":\"$logs_size\",\"last_modified\":\"$last_modified\",\"permissions\":\"$permissions\",\"cpu_usage\":\"$cpu_usage\",\"mem_usage\":\"$mem_usage\",\"pid\":\"$pid\"}"
}

# Função para obter logs recentes
get_recent_logs() {
    local domain=$1
    local site_dir="/home/carlo/sites/$domain"
    
    # Log da aplicação
    local app_log="$site_dir/logs/app.log"
    local app_log_lines=""
    if [ -f "$app_log" ]; then
        app_log_lines=$(tail -n 10 "$app_log" 2>/dev/null | jq -R . | jq -s .)
    else
        app_log_lines="[]"
    fi
    
    # Log de erro
    local error_log="$site_dir/logs/error.log"
    local error_log_lines=""
    if [ -f "$error_log" ]; then
        error_log_lines=$(tail -n 5 "$error_log" 2>/dev/null | jq -R . | jq -s .)
    else
        error_log_lines="[]"
    fi
    
    # Status dos arquivos de log
    local app_log_size=$(du -h "$app_log" 2>/dev/null | cut -f1 || echo "0")
    local error_log_size=$(du -h "$error_log" 2>/dev/null | cut -f1 || echo "0")
    
    echo "{\"app_log_lines\":$app_log_lines,\"error_log_lines\":$error_log_lines,\"app_log_size\":\"$app_log_size\",\"error_log_size\":\"$error_log_size\"}"
}

# Função para obter informações Nginx
get_nginx_info() {
    local domain=$1
    local nginx_conf="/home/carlo/nginx/sites-available/$domain"
    
    local config_exists=false
    local ssl_configured=false
    local domains_configured=""
    
    if [ -f "$nginx_conf" ]; then
        config_exists=true
        if grep -q "ssl_certificate" "$nginx_conf"; then
            ssl_configured=true
        fi
        domains_configured=$(grep "server_name" "$nginx_conf" | sed 's/server_name//' | xargs)
    fi
    
    echo "{\"config_exists\":$config_exists,\"ssl_configured\":$ssl_configured,\"domains_configured\":\"$domains_configured\"}"
}

# Coletar todas as informações
basic_info=$(get_basic_info "$DOMAIN")
supervisor_info=$(get_supervisor_status "$DOMAIN")
port_info=$(get_port_info "$DOMAIN")
deploy_info=$(get_deploy_info "$DOMAIN")
ssl_info=$(get_ssl_info "$DOMAIN")
system_info=$(get_system_info "$DOMAIN")
logs_info=$(get_recent_logs "$DOMAIN")
nginx_info=$(get_nginx_info "$DOMAIN")

# Output
if [ "$JSON_OUTPUT" = true ]; then
    # Output JSON para interface web
    echo "{\"basic_info\":$basic_info,\"supervisor_info\":$supervisor_info,\"port_info\":$port_info,\"deploy_info\":$deploy_info,\"ssl_info\":$ssl_info,\"system_info\":$system_info,\"logs_info\":$logs_info,\"nginx_info\":$nginx_info,\"timestamp\":\"$(date -Iseconds)\"}"
elif [ "$HTML_OUTPUT" = true ]; then
    # Output HTML para exibição direta
    echo "<div class='site-details'>"
    echo "<h2>Detalhes do Site: $DOMAIN</h2>"
    echo "<div class='info-section'>"
    echo "<h3>Informações Básicas</h3>"
    echo "<p><strong>Domínio:</strong> $DOMAIN</p>"
    echo "<p><strong>Porta:</strong> $(echo "$port_info" | jq -r '.port')</p>"
    echo "<p><strong>Framework:</strong> $(echo "$basic_info" | jq -r '.framework')</p>"
    echo "<p><strong>Python:</strong> $(echo "$basic_info" | jq -r '.python_version')</p>"
    echo "<p><strong>Status:</strong> $(echo "$supervisor_info" | jq -r '.status')</p>"
    echo "</div>"
    echo "</div>"
else
    # Output formatado para terminal
    echo -e "${CYAN}🐍 DETALHES DO SITE - $DOMAIN${NC}"
    echo "=================================="
    echo ""
    
    # Informações básicas
    echo -e "${BLUE}📋 INFORMAÇÕES BÁSICAS${NC}"
    echo "   Domínio: $DOMAIN"
    echo "   Porta: $(echo "$port_info" | jq -r '.port')"
    echo "   Framework: $(echo "$basic_info" | jq -r '.framework')"
    echo "   Python: $(echo "$basic_info" | jq -r '.python_version')"
    echo "   Status: $(echo "$supervisor_info" | jq -r '.status')"
    echo "   Criado em: $(echo "$basic_info" | jq -r '.created_at')"
    echo ""
    
    # Status do sistema
    echo -e "${GREEN}🔧 STATUS DO SISTEMA${NC}"
    echo "   Supervisor: $(echo "$supervisor_info" | jq -r '.supervisor_status')"
    echo "   PID: $(echo "$system_info" | jq -r '.pid')"
    echo "   Porta: $(echo "$port_info" | jq -r '.status')"
    echo "   CPU: $(echo "$system_info" | jq -r '.cpu_usage')%"
    echo "   Memória: $(echo "$system_info" | jq -r '.mem_usage')%"
    echo ""
    
    # Informações de deploy
    github_repo=$(echo "$deploy_info" | jq -r '.github_repo')
    if [ "$github_repo" != "" ] && [ "$github_repo" != "null" ]; then
        echo -e "${PURPLE}🚀 INFORMAÇÕES DE DEPLOY${NC}"
        echo "   Repositório: $github_repo"
        echo "   Branch: $(echo "$deploy_info" | jq -r '.github_branch')"
        echo "   Último deploy: $(echo "$deploy_info" | jq -r '.last_deploy')"
        echo "   Releases: $(echo "$deploy_info" | jq -r '.releases_count')"
        echo "   Release atual: $(echo "$deploy_info" | jq -r '.current_release')"
        echo ""
    fi
    
    # Informações SSL
    ssl_enabled=$(echo "$ssl_info" | jq -r '.enabled')
    if [ "$ssl_enabled" = "true" ]; then
        echo -e "${YELLOW}🔒 INFORMAÇÕES SSL${NC}"
        echo "   Status: $(echo "$ssl_info" | jq -r '.status')"
        echo "   Expira em: $(echo "$ssl_info" | jq -r '.expiry_date')"
        echo "   Dias restantes: $(echo "$ssl_info" | jq -r '.days_until_expiry')"
        echo "   Emitente: $(echo "$ssl_info" | jq -r '.issuer')"
        echo ""
    else
        echo -e "${YELLOW}🔒 SSL${NC}"
        echo "   Status: Não instalado"
        echo ""
    fi
    
    # Informações de sistema
    echo -e "${CYAN}💾 INFORMAÇÕES DE SISTEMA${NC}"
    echo "   Tamanho do diretório: $(echo "$system_info" | jq -r '.dir_size')"
    echo "   Tamanho dos logs: $(echo "$system_info" | jq -r '.logs_size')"
    echo "   Última modificação: $(echo "$system_info" | jq -r '.last_modified')"
    echo "   Permissões: $(echo "$system_info" | jq -r '.permissions')"
    echo ""
    
    # Informações Nginx
    config_exists=$(echo "$nginx_info" | jq -r '.config_exists')
    if [ "$config_exists" = "true" ]; then
        echo -e "${ORANGE}🌐 CONFIGURAÇÃO NGINX${NC}"
        echo "   Configuração: Existe"
        echo "   SSL configurado: $(echo "$nginx_info" | jq -r '.ssl_configured')"
        echo "   Domínios: $(echo "$nginx_info" | jq -r '.domains_configured')"
        echo ""
    fi
    
    # Logs recentes
    echo -e "${BLUE}📝 LOGS RECENTES${NC}"
    echo "   Log da aplicação: $(echo "$logs_info" | jq -r '.app_log_size')"
    echo "   Log de erro: $(echo "$logs_info" | jq -r '.error_log_size')"
    echo ""
    
    # Comandos úteis
    echo -e "${CYAN}💡 COMANDOS ÚTEIS${NC}"
    echo "   ./carlo-start-site.sh $DOMAIN    # Iniciar site"
    echo "   ./carlo-stop-site.sh $DOMAIN     # Parar site"
    echo "   ./carlo-logs.sh $DOMAIN          # Ver logs"
    echo "   ./carlo-ssl-status.sh $DOMAIN    # Status SSL"
    echo "   ./carlo-nginx-edit.sh $DOMAIN    # Editar Nginx"
    echo "   ./carlo-delete-site.sh $DOMAIN   # Deletar site"
fi 