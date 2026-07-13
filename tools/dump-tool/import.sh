#!/bin/bash
set -euo pipefail

# =============================================================================
# import.sh — Restaura el dump reducido en la base de datos local.
#
# Uso:
#   ./import.sh [--skip-schema] [--only-schema] [--drop-schema]
#
# Requiere haber ejecutado export.sh previamente.
# La base de datos local debe existir antes de importar.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/common.sh"

SCHEMA_FILE="${OUTPUT_DIR}/schema.sql"
DATA_FILE="${OUTPUT_DIR}/data.sql"

SKIP_SCHEMA=false
ONLY_SCHEMA=false
DROP_SCHEMA=false

usage() {
    cat <<EOF
Uso: ./import.sh [opciones]

Opciones:
  --skip-schema   Omite la importación del esquema (asume que ya existe en la base local).
  --only-schema   Importa solo el esquema y termina (no importa los datos).
  --drop-schema   Elimina (CASCADE) el esquema \${LOCAL_DB_SCHEMA} existente en la base local antes de importar.
  -h, --help      Muestra esta ayuda.
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-schema) SKIP_SCHEMA=true; shift ;;
        --only-schema) ONLY_SCHEMA=true; shift ;;
        --drop-schema) DROP_SCHEMA=true; shift ;;
        -h|--help) usage ;;
        *) die "Opción desconocida: $1 (usar --help)" ;;
    esac
done

if [[ "$DROP_SCHEMA" == true && "$SKIP_SCHEMA" == true ]]; then
    die "--drop-schema y --skip-schema son excluyentes."
fi

_local_psql() {
    PGPASSWORD="${LOCAL_DB_PASSWORD}" psql \
        -h "${LOCAL_DB_HOST}" \
        -p "${LOCAL_DB_PORT}" \
        -U "${LOCAL_DB_USER}" \
        -d "${LOCAL_DB_NAME}" \
        "$@"
}

drop_local_schema() {
    require_var "LOCAL_DB_SCHEMA"
    log_step "Eliminando esquema '${LOCAL_DB_SCHEMA}' de la base local (CASCADE)..."
    _local_psql -v ON_ERROR_STOP=1 -c "DROP SCHEMA IF EXISTS ${LOCAL_DB_SCHEMA} CASCADE;"
    log_success "Esquema '${LOCAL_DB_SCHEMA}' eliminado."
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

    check_dependencies
    verify_local_connection

    if [[ "$SKIP_SCHEMA" == true ]]; then
        log_info "Omitiendo importación de esquema (--skip-schema)."
    else
        [[ -f "$SCHEMA_FILE" ]] || die "Esquema no encontrado: $SCHEMA_FILE. Ejecutar export.sh primero."

        if [[ "$DROP_SCHEMA" == true ]]; then
            drop_local_schema
        fi

        log_step "Importando esquema..."
        _local_psql -q -f "$SCHEMA_FILE"
        log_success "Esquema importado."
    fi

    if [[ "$ONLY_SCHEMA" == true ]]; then
        log_success "Esquema listo (--only-schema). Finalizando sin importar datos."
        exit 0
    fi

    [[ -f "$DATA_FILE" ]] || die "Datos no encontrados: $DATA_FILE. Ejecutar export.sh primero."
    log_step "Importando datos..."
    _local_psql -q -f "$DATA_FILE"
    log_success "Datos importados."

    echo ""
    log_step "========================================="
    log_success " Importación completada"
    log_step "========================================="
}

main "$@"
