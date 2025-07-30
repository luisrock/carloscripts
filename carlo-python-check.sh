#!/bin/bash
# ========================================
# CARLO PYTHON CHECK SCRIPT
# ========================================
# Diagnostica e corrige problemas de Python no sistema Carlo
# Uso: ./carlo-python-check.sh [--fix]

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
FIX_MODE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --fix)
            FIX_MODE=true
            shift
            ;;
        *)
            echo "Uso: $0 [--fix]"
            exit 1
            ;;
    esac
done

echo -e "${CYAN}🔍 DIAGNÓSTICO PYTHON - CARLO DEPLOY${NC}"
echo "=========================================="
echo ""

# Verificar Python 3
log "Verificando Python 3..."
PYTHON3_FOUND=false
PYTHON3_VERSION=""

if command -v python3 &> /dev/null; then
    PYTHON3_FOUND=true
    PYTHON3_VERSION=$(python3 --version 2>&1)
    success "Python 3 encontrado: $PYTHON3_VERSION"
else
    error "Python 3 não encontrado no PATH"
fi

# Verificar Python (fallback)
log "Verificando Python (fallback)..."
PYTHON_FOUND=false
PYTHON_VERSION=""

if command -v python &> /dev/null; then
    PYTHON_FOUND=true
    PYTHON_VERSION=$(python --version 2>&1)
    success "Python encontrado: $PYTHON_VERSION"
else
    warning "Python não encontrado no PATH"
fi

# Verificar caminhos absolutos
log "Verificando caminhos absolutos..."
ABSOLUTE_PATHS=()

for path in "/usr/bin/python3" "/usr/local/bin/python3" "/opt/python3/bin/python3"; do
    if [ -f "$path" ]; then
        ABSOLUTE_PATHS+=("$path")
        success "Python encontrado em: $path"
    fi
done

# Verificar python3-venv
log "Verificando python3-venv..."
VENV_AVAILABLE=false

if python3 -c "import venv" 2>/dev/null; then
    VENV_AVAILABLE=true
    success "python3-venv disponível"
else
    error "python3-venv não disponível"
fi

# Verificar pip3
log "Verificando pip3..."
PIP3_AVAILABLE=false

if command -v pip3 &> /dev/null; then
    PIP3_AVAILABLE=true
    success "pip3 disponível: $(pip3 --version)"
else
    error "pip3 não encontrado"
fi

# Verificar pip
log "Verificando pip..."
PIP_AVAILABLE=false

if command -v pip &> /dev/null; then
    PIP_AVAILABLE=true
    success "pip disponível: $(pip --version)"
else
    warning "pip não encontrado"
fi

# Testar criação de ambiente virtual
log "Testando criação de ambiente virtual..."
TEMP_DIR="/tmp/carlo_python_test_$$"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

VENV_TEST_PASSED=false
if $PYTHON3_FOUND; then
    if python3 -m venv test_venv 2>/dev/null; then
        VENV_TEST_PASSED=true
        success "Teste de ambiente virtual passou"
        rm -rf test_venv
    else
        error "Falha no teste de ambiente virtual"
    fi
fi

# Resumo
echo ""
echo -e "${CYAN}📊 RESUMO DO DIAGNÓSTICO${NC}"
echo "================================"
echo "Python 3: $([ "$PYTHON3_FOUND" = true ] && echo "✅" || echo "❌")"
echo "Python: $([ "$PYTHON_FOUND" = true ] && echo "✅" || echo "❌")"
echo "python3-venv: $([ "$VENV_AVAILABLE" = true ] && echo "✅" || echo "❌")"
echo "pip3: $([ "$PIP3_AVAILABLE" = true ] && echo "✅" || echo "❌")"
echo "pip: $([ "$PIP_AVAILABLE" = true ] && echo "✅" || echo "❌")"
echo "Teste venv: $([ "$VENV_TEST_PASSED" = true ] && echo "✅" || echo "❌")"
echo ""

# Se --fix foi especificado, tentar corrigir problemas
if [ "$FIX_MODE" = true ]; then
    echo -e "${CYAN}🔧 CORRIGINDO PROBLEMAS PYTHON${NC}"
    echo "=================================="
    echo ""
    
    # Instalar Python 3 se necessário
    if [ "$PYTHON3_FOUND" = false ]; then
        log "Instalando Python 3..."
        sudo apt update
        sudo apt install -y python3 python3-pip python3-venv python3-dev
    fi
    
    # Instalar python3-venv se necessário
    if [ "$VENV_AVAILABLE" = false ]; then
        log "Instalando python3-venv..."
        sudo apt update
        sudo apt install -y python3-venv
    fi
    
    # Instalar pip se necessário
    if [ "$PIP3_AVAILABLE" = false ]; then
        log "Instalando pip3..."
        sudo apt update
        sudo apt install -y python3-pip
    fi
    
    # Verificar se as correções funcionaram
    echo ""
    log "Verificando correções..."
    
    if command -v python3 &> /dev/null && python3 -c "import venv" 2>/dev/null; then
        success "Problemas Python corrigidos!"
        echo ""
        echo "✅ Python 3: $(python3 --version)"
        echo "✅ python3-venv: Disponível"
        echo "✅ pip3: $(pip3 --version)"
        echo ""
        echo "🎉 O sistema Python está pronto para uso!"
    else
        error "Falha ao corrigir problemas Python"
        echo ""
        echo "💡 Tente manualmente:"
        echo "   sudo apt update"
        echo "   sudo apt install python3 python3-pip python3-venv python3-dev"
        echo "   sudo apt install build-essential"
    fi
else
    # Sugestões de correção
    echo -e "${CYAN}💡 SUGESTÕES DE CORREÇÃO${NC}"
    echo "=============================="
    echo ""
    
    if [ "$PYTHON3_FOUND" = false ] || [ "$VENV_AVAILABLE" = false ] || [ "$PIP3_AVAILABLE" = false ]; then
        echo "Execute: $0 --fix"
        echo ""
        echo "Ou manualmente:"
        echo "   sudo apt update"
        echo "   sudo apt install python3 python3-pip python3-venv python3-dev"
        echo "   sudo apt install build-essential"
    fi
    
    if [ "$VENV_TEST_PASSED" = false ]; then
        echo ""
        echo "🔧 Para problemas de ambiente virtual:"
        echo "   sudo apt install python3-venv"
        echo "   python3 -m ensurepip --upgrade"
    fi
fi

# Limpar
rm -rf "$TEMP_DIR"

echo ""
echo -e "${CYAN}💡 Comandos úteis:${NC}"
echo "   $0 --fix                    # Corrigir problemas automaticamente"
echo "   python3 --version           # Verificar versão Python"
echo "   python3 -c 'import venv'    # Testar módulo venv"
echo "   pip3 --version              # Verificar versão pip" 