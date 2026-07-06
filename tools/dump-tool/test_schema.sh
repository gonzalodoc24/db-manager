#!/bin/bash
set -euo pipefail

# Descarga el esquema y construye el grafo de dependencias.
# Útil para verificar la conexión y revisar las FK antes del export completo.
# Uso: ./test_schema.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/ssh.sh"
source "${SCRIPT_DIR}/lib/postgres.sh"
source "${SCRIPT_DIR}/lib/schema.sh"

SCHEMA_FILE="${OUTPUT_DIR}/schema.sql"

cleanup() { stop_ssh_tunnel; }
trap cleanup EXIT

check_dependencies
mkdir -p "$OUTPUT_DIR"
init_error_log

log_step "Abriendo túnel SSH..."
start_ssh_tunnel

log_step "Verificando conexión..."
verify_connection

log_step "Descargando esquema..."
download_schema "$SCHEMA_FILE"

log_step "Construyendo grafo de dependencias..."
build_dependency_graph

log_step "Resumen del grafo:"
print_graph_summary

fk_count=$(wc -l < "$GRAPH_FILE")
log_success "Listo. ${fk_count} FKs en ${GRAPH_FILE}"
