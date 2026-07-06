#!/bin/bash
set -euo pipefail

# =============================================================================
# export.sh — Genera el dump reducido de la base de datos remota.
#
# Uso:
#   ./export.sh
#
# El proceso:
#   1. Abre el túnel SSH.
#   2. Verifica la conexión con la base de datos.
#   3. Descarga el esquema completo.
#   4. Construye el grafo de dependencias desde las FK del esquema.
#   5. Genera el dump reducido (tablas estáticas + datos filtrados por brand).
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/ssh.sh"
source "${SCRIPT_DIR}/lib/postgres.sh"
source "${SCRIPT_DIR}/lib/schema.sh"
source "${SCRIPT_DIR}/lib/reduced_dump.sh"

SCHEMA_FILE="${OUTPUT_DIR}/schema.sql"

cleanup() {
    stop_ssh_tunnel
}
trap cleanup EXIT

main() {
    log_step "========================================="
    log_step " dump-tool — exportación iniciada"
    log_step "========================================="
    log_info "Brand:          ${BRAND}"
    log_info "Tabla principal: ${MAIN_TABLE} (últimos ${MAIN_TABLE_LIMIT})"
    log_info "Directorio:     ${OUTPUT_DIR}"
    echo ""

    check_dependencies
    mkdir -p "$OUTPUT_DIR"
    init_error_log

    # 1. Túnel SSH
    start_ssh_tunnel

    # 2. Verificar conexión
    verify_connection

    # 3. Esquema
    download_schema "$SCHEMA_FILE"

    # 4. Grafo de dependencias
    build_dependency_graph

    # 5. Dump reducido
    generate_reduced_dump

    echo ""
    log_step "========================================="
    log_success " Exportación completada"
    log_step "========================================="
    log_info "Esquema:  $SCHEMA_FILE"
    log_info "Datos:    ${OUTPUT_DIR}/data.sql"
    log_info "Grafo FK: ${OUTPUT_DIR}/dependency_graph.tsv"
    echo ""
    log_info "Para importar en la base local ejecutar: ./import.sh"
}

main "$@"
