#!/bin/bash
set -euo pipefail

# Prueba el túnel SSH y la conexión con la base de datos.
# Uso: ./connection.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/ssh.sh"
source "${SCRIPT_DIR}/lib/postgres.sh"

cleanup() { stop_ssh_tunnel; }
trap cleanup EXIT

check_dependencies
mkdir -p "$OUTPUT_DIR"
init_error_log

log_info "Prueba de túnel SSH y conexión a la DB"
log_step "Abriendo túnel SSH..."
start_ssh_tunnel

log_step "Verificando conexión con la base de datos..."
verify_connection

log_step "Ejecutando query de prueba..."
result=$(run_sql "SELECT version();")
log_success "Respuesta del servidor: ${result}"
