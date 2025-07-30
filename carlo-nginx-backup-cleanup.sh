#!/bin/bash
# ========================================
# CARLO NGINX BACKUP CLEANUP SCRIPT
# ========================================
# Limpa backups antigos de configurações Nginx
# Mantém apenas os últimos 3 backups por site
# Remove backups muito pequenos (< 100 bytes)
# Uso: ./carlo-nginx-backup-cleanup.sh [--dry-run] [--verbose]

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Função para log
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCESSO]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

error() {
    echo -e "${RED}[ERRO]${NC} $1"
}

# Configurações
BACKUP_DIR="/home/carlo/nginx/sites-available"
MAX_BACKUPS=3
MIN_SIZE=100
DRY_RUN=false
VERBOSE=false

# Processar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Uso: $0 [--dry-run] [--verbose]"
            echo "  --dry-run: Mostra o que seria feito sem executar"
            echo "  --verbose: Mostra detalhes de cada operação"
            exit 1
            ;;
    esac
done

# Verificar se o diretório existe
if [ ! -d "$BACKUP_DIR" ]; then
    error "Diretório de backups não encontrado: $BACKUP_DIR"
    exit 1
fi

log "Iniciando limpeza de backups Nginx..."
if [ "$DRY_RUN" = true ]; then
    warning "MODO DRY-RUN: Nenhum arquivo será removido"
fi

# Estatísticas iniciais
total_backups_before=$(find "$BACKUP_DIR" -name "*.backup.*" | wc -l)
total_size_before=$(find "$BACKUP_DIR" -name "*.backup.*" -exec du -c {} + | tail -1 | cut -f1)

echo "📊 Estatísticas iniciais:"
echo "  Total de backups: $total_backups_before"
echo "  Tamanho total: ${total_size_before}K"

# Para cada site, manter apenas os últimos MAX_BACKUPS backups
sites_processed=0
backups_removed=0

for site in $(find "$BACKUP_DIR" -name "*.backup.*" | sed 's/.*\///' | sed 's/\.backup\..*//' | sort | uniq); do
    echo ""
    echo "📁 Processando site: $site"
    
    # Listar backups do site (mais recentes primeiro)
    backups=($(ls -t "$BACKUP_DIR/$site.backup."* 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ]; then
        echo "  Nenhum backup encontrado"
        continue
    fi
    
    sites_processed=$((sites_processed + 1))
    echo "  Total de backups: ${#backups[@]}"
    
    # Manter apenas os últimos MAX_BACKUPS
    if [ ${#backups[@]} -gt $MAX_BACKUPS ]; then
        to_remove=(${backups[@]:MAX_BACKUPS})
        echo "  Removendo ${#to_remove[@]} backups antigos:"
        
        for backup in "${to_remove[@]}"; do
            size=$(stat -c%s "$backup" 2>/dev/null || echo 0)
            echo "    - $(basename $backup) (${size} bytes)"
            
            if [ "$DRY_RUN" = false ]; then
                rm -f "$backup"
                backups_removed=$((backups_removed + 1))
            fi
        done
    else
        echo "  Mantendo todos os ${#backups[@]} backups (dentro do limite)"
    fi
    
    # Remover backups muito pequenos
    for backup in "${backups[@]}"; do
        size=$(stat -c%s "$backup" 2>/dev/null || echo 0)
        if [ $size -lt $MIN_SIZE ]; then
            echo "  Removendo backup muito pequeno: $(basename $backup) (${size} bytes)"
            if [ "$DRY_RUN" = false ]; then
                rm -f "$backup"
                backups_removed=$((backups_removed + 1))
            fi
        fi
    done
done

# Estatísticas finais
total_backups_after=$(find "$BACKUP_DIR" -name "*.backup.*" | wc -l)
total_size_after=$(find "$BACKUP_DIR" -name "*.backup.*" -exec du -c {} + | tail -1 | cut -f1 2>/dev/null || echo "0")

echo ""
echo "📊 Estatísticas finais:"
echo "  Sites processados: $sites_processed"
echo "  Backups removidos: $backups_removed"
echo "  Total de backups: $total_backups_after (era $total_backups_before)"
echo "  Tamanho total: ${total_size_after}K (era ${total_size_before}K)"

# Mostrar breakdown por site
echo ""
echo "📋 Breakdown por site:"
for site in $(find "$BACKUP_DIR" -name "*.backup.*" | sed 's/.*\///' | sed 's/\.backup\..*//' | sort | uniq); do
    count=$(ls "$BACKUP_DIR/$site.backup."* 2>/dev/null | wc -l)
    echo "  $site: $count backups"
done

if [ "$DRY_RUN" = true ]; then
    warning "Dry-run concluído. Execute sem --dry-run para aplicar as mudanças."
else
    success "Limpeza de backups Nginx concluída!"
fi 