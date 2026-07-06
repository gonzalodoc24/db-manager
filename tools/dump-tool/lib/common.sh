#!/bin/bash

# =============================================================================
# Colores y funciones de logging
# =============================================================================

RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
CYAN='\e[36m'
RESET='\e[0m'

log_info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
log_success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_step()    { echo -e "${BLUE}[STEP]${RESET}  $*"; }

die() {
    log_error "$*"
    exit 1
}

require_var() {
    local var_name="$1"
    local var_value="${!var_name}"
    [[ -n "$var_value" ]] || die "Variable requerida no configurada: ${var_name}. Verificar config.sh."
}

# Verifica que los binarios necesarios estén disponibles.
check_dependencies() {
    local deps=("ssh" "${PSQL_BIN:-psql}" "${PG_DUMP_BIN:-pg_dump}" "${PG_ISREADY_BIN:-pg_isready}")
    for dep in "${deps[@]}"; do
        command -v "$dep" > /dev/null 2>&1 || die "Dependencia no encontrada: $dep"
    done
}

# Limpia el log de errores al inicio de cada ejecución.
init_error_log() {
    mkdir -p "$(dirname "${ERROR_LOG}")"
    > "${ERROR_LOG}"
}

# Muestra las primeras líneas del log de errores en stderr, truncando líneas largas.
# Llamar después de un comando fallido para dar contexto sin saturar la terminal.
_ERROR_LOG_MAX_LINES=5
_ERROR_LOG_MAX_CHARS=120

show_error_log() {
    if [[ -s "${ERROR_LOG}" ]]; then
        log_error "--- ${ERROR_LOG} ---"
        head -${_ERROR_LOG_MAX_LINES} "${ERROR_LOG}" \
            | cut -c1-${_ERROR_LOG_MAX_CHARS} \
            | while IFS= read -r line; do
                echo -e "${RED}${line}${RESET}" >&2
            done
        log_error "--- log completo en: ${ERROR_LOG} ---"
    fi
}
