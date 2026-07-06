#!/bin/bash
set -euo pipefail

# =============================================================================
# import.sh — Restaura el dump reducido en la base de datos local.
#
# Uso:
#   ./import.sh
#
# Requiere haber ejecutado export.sh previamente.
# La base de datos local debe existir antes de importar.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/common.sh"

SCHEMA_FILE="${OUTPUT_DIR}/schema.sql"
# DATA_FILE="${OUTPUT_DIR}/data.sql"

_local_psql() {
    PGPASSWORD="${LOCAL_DB_PASSWORD}" psql \
        -h "${LOCAL_DB_HOST}" \
        -p "${LOCAL_DB_PORT}" \
        -U "${LOCAL_DB_USER}" \
        -d "${LOCAL_DB_NAME}" \
        "$@"
}

verify_local_connection() {
    log_info "Verificando conexión con la base local (${LOCAL_DB_NAME})..."
    PGPASSWORD="${LOCAL_DB_PASSWORD}" pg_isready \
        -h "${LOCAL_DB_HOST}" \
        -p "${LOCAL_DB_PORT}" \
        -U "${LOCAL_DB_USER}" \
        -d "${LOCAL_DB_NAME}" \
        -t 5 || die "No se puede conectar a la base local. Verificar configuración."
    log_success "Conexión local OK."
}

main() {
    log_step "========================================="
    log_step " dump-tool — importación iniciada"
    log_step "========================================="
    log_info "Base local: ${LOCAL_DB_NAME} @ ${LOCAL_DB_HOST}:${LOCAL_DB_PORT}"
    echo ""

    [[ -f "$SCHEMA_FILE" ]] || die "Esquema no encontrado: $SCHEMA_FILE. Ejecutar export.sh primero."
    # [[ -f "$DATA_FILE" ]]   || die "Datos no encontrados: $DATA_FILE. Ejecutar export.sh primero."

    check_dependencies
    verify_local_connection

    log_step "Importando esquema..."
    _local_psql -f "$SCHEMA_FILE"
    log_success "Esquema importado."

    # log_step "Importando datos..."
    # _local_psql -f "$DATA_FILE"
    # log_success "Datos importados."

    echo ""
    log_step "========================================="
    log_success " Importación completada"
    log_step "========================================="
}

main "$@"
