#!/bin/bash
# ========================================
# CARLO SSL STATUS SCRIPT
# ========================================
# Verifica status dos certificados SSL Let's Encrypt
# Uso: ./carlo-ssl-status.sh <domain> [--json] [--all]

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

# Verificar argumentos
JSON_OUTPUT=false
SHOW_ALL=false
DOMAIN=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --all)
            SHOW_ALL=true
            shift
            ;;
        *)
            if [ -z "$DOMAIN" ]; then
                DOMAIN=$1
            else
                echo "Uso: $0 <domain> [--json] [--all]"
                exit 1
            fi
            shift
            ;;
    esac
done

# Função para obter status SSL de um domínio
get_ssl_status() {
    local domain=$1
    local site_dir="/home/carlo/sites/$domain"
    local cert_file="/home/carlo/ssl/$domain/live/cert.pem"
    
    # Verificar se o site existe
    if [ ! -d "$site_dir" ]; then
        if [ "$JSON_OUTPUT" = true ]; then
            echo "{\"domain\":\"$domain\",\"ssl_enabled\":false,\"error\":\"Site não encontrado\"}"
        else
            echo -e "${RED}❌ $domain: Site não encontrado${NC}"
        fi
        return 1
    fi
    
    # Verificar se tem certificado SSL
    if [ ! -f "$cert_file" ]; then
        if [ "$JSON_OUTPUT" = true ]; then
            echo "{\"domain\":\"$domain\",\"ssl_enabled\":false,\"error\":\"Certificado SSL não encontrado\"}"
        else
            echo -e "${YELLOW}⚠️  $domain: Sem certificado SSL${NC}"
        fi
        return 1
    fi
    
    # Obter informações do certificado
    local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
    local start_date=$(openssl x509 -in "$cert_file" -noout -startdate 2>/dev/null | cut -d= -f2)
    local issuer=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null | sed 's/issuer=//')
    local subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed 's/subject=//')
    local serial=$(openssl x509 -in "$cert_file" -noout -serial 2>/dev/null | sed 's/serial=//')
    
    # Verificar se o certificado é válido
    local current_timestamp=$(date +%s)
    local expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null)
    local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
    
    # Determinar status
    local status="valid"
    local status_color="${GREEN}"
    local status_icon="✅"
    
    if [ "$days_until_expiry" -lt 0 ]; then
        status="expired"
        status_color="${RED}"
        status_icon="❌"
    elif [ "$days_until_expiry" -lt 7 ]; then
        status="critical"
        status_color="${RED}"
        status_icon="🚨"
    elif [ "$days_until_expiry" -lt 30 ]; then
        status="warning"
        status_color="${YELLOW}"
        status_icon="⚠️"
    fi
    
    # Verificar se o certificado está sendo usado pelo Nginx
    local nginx_using_ssl=false
    if [ -f "/home/carlo/nginx/sites-available/$domain" ]; then
        if grep -q "ssl_certificate.*$domain" "/home/carlo/nginx/sites-available/$domain"; then
            nginx_using_ssl=true
        fi
    fi
    
    # Output
    if [ "$JSON_OUTPUT" = true ]; then
        echo "{\"domain\":\"$domain\",\"ssl_enabled\":true,\"status\":\"$status\",\"expiry_date\":\"$expiry_date\",\"days_until_expiry\":$days_until_expiry,\"issuer\":\"$issuer\",\"subject\":\"$subject\",\"serial\":\"$serial\",\"nginx_using_ssl\":$nginx_using_ssl,\"cert_file\":\"$cert_file\"}"
    else
        echo -e "${status_color}${status_icon} $domain:${NC}"
        echo "   Status: $status"
        echo "   Expira em: $expiry_date ($days_until_expiry dias)"
        echo "   Emitente: $issuer"
        echo "   Nginx SSL: $nginx_using_ssl"
        echo ""
    fi
    
    return 0
}

# Se --all foi especificado, verificar todos os sites
if [ "$SHOW_ALL" = true ]; then
    if [ "$JSON_OUTPUT" = true ]; then
        echo "["
        first=true
        for site_dir in /home/carlo/sites/*/; do
            if [ -d "$site_dir" ]; then
                domain=$(basename "$site_dir")
                if [ "$first" = true ]; then
                    first=false
                else
                    echo ","
                fi
                get_ssl_status "$domain"
            fi
        done
        echo "]"
    else
        echo -e "${CYAN}🔒 STATUS SSL - TODOS OS SITES${NC}"
        echo "=================================="
        echo ""
        
        ssl_enabled=0
        ssl_disabled=0
        expired=0
        warning=0
        valid=0
        
        for site_dir in /home/carlo/sites/*/; do
            if [ -d "$site_dir" ]; then
                domain=$(basename "$site_dir")
                if get_ssl_status "$domain" > /tmp/ssl_status_$domain; then
                    ((ssl_enabled++))
                    # Contar por status
                    if grep -q "Status: expired" /tmp/ssl_status_$domain; then
                        ((expired++))
                    elif grep -q "Status: warning" /tmp/ssl_status_$domain; then
                        ((warning++))
                    elif grep -q "Status: valid" /tmp/ssl_status_$domain; then
                        ((valid++))
                    fi
                else
                    ((ssl_disabled++))
                fi
            fi
        done
        
        echo ""
        echo -e "${CYAN}📊 RESUMO:${NC}"
        echo "   ✅ SSL Ativo: $ssl_enabled"
        echo "   ❌ SSL Inativo: $ssl_disabled"
        echo "   🚨 Expirados: $expired"
        echo "   ⚠️  Aviso (<30 dias): $warning"
        echo "   ✅ Válidos: $valid"
        echo ""
        
        # Limpar arquivos temporários
        rm -f /tmp/ssl_status_*
    fi
    
    exit 0
fi

# Verificar se o domínio foi fornecido
if [ -z "$DOMAIN" ]; then
    error "Uso: $0 <domain> [--json]"
    echo "       $0 --all [--json]"
    echo ""
    echo "Exemplos:"
    echo "  $0 meusite.com              # Verificar SSL específico"
    echo "  $0 meusite.com --json       # Output JSON"
    echo "  $0 --all                    # Verificar todos os SSL"
    echo "  $0 --all --json             # Output JSON para todos"
    exit 1
fi

# Verificar SSL específico
if [ "$JSON_OUTPUT" = true ]; then
    get_ssl_status "$DOMAIN"
else
    echo -e "${CYAN}🔒 STATUS SSL - $DOMAIN${NC}"
    echo "=========================="
    echo ""
    get_ssl_status "$DOMAIN"
    
    echo ""
    echo -e "${CYAN}💡 Comandos úteis:${NC}"
    echo "   ./carlo-ssl-setup.sh $DOMAIN    # Instalar SSL"
    echo "   ./carlo-ssl-renew.sh $DOMAIN    # Renovar SSL"
    echo "   ./carlo-nginx-edit.sh $DOMAIN   # Editar Nginx"
fi 