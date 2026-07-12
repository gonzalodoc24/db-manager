#!/bin/bash
set -euo pipefail

# =============================================================================
# export.sh — Genera el dump reducido de la base de datos remota.
#
# Uso:
#   ./export.sh [--skip-schema] [--skip-graph]
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
# GRAPH_FILE ya queda definido por lib/schema.sh al sourcearlo arriba.

SKIP_SCHEMA=false
SKIP_GRAPH=false

usage() {
    cat <<EOF
Uso: ./export.sh [opciones]

Opciones:
  --skip-schema   Omite la descarga del esquema y reutiliza ${SCHEMA_FILE}.
  --skip-graph    Omite la reconstrucción del grafo de FK y reutiliza ${GRAPH_FILE}.
  -h, --help      Muestra esta ayuda.
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-schema) SKIP_SCHEMA=true; shift ;;
        --skip-graph) SKIP_GRAPH=true; shift ;;
        -h|--help) usage ;;
        *) die "Opción desconocida: $1 (usar --help)" ;;
    esac
done

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
    if [[ "$SKIP_SCHEMA" == true ]]; then
        [[ -f "$SCHEMA_FILE" ]] || die "No se puede omitir el esquema: no existe ${SCHEMA_FILE}. Ejecutar sin --skip-schema al menos una vez."
        log_info "Omitiendo descarga de esquema (--skip-schema). Usando: ${SCHEMA_FILE}"
    else
        download_schema "$SCHEMA_FILE"
    fi

    # 4. Grafo de dependencias
    if [[ "$SKIP_GRAPH" == true ]]; then
        [[ -f "$GRAPH_FILE" ]] || die "No se puede omitir el grafo: no existe ${GRAPH_FILE}. Ejecutar sin --skip-graph al menos una vez."
        log_info "Omitiendo reconstrucción del grafo (--skip-graph). Usando: ${GRAPH_FILE}"
    else
        build_dependency_graph
    fi

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
