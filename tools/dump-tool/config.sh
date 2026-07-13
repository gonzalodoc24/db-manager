#!/bin/bash

# =============================================================================
# Carga credenciales y valores de entorno desde .env .
# Copiar .env.example como .env y completar los valores antes de usar.
# =============================================================================
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_ENV_FILE="${_SCRIPT_DIR}/.env"

if [[ ! -f "$_ENV_FILE" ]]; then
    echo "[ERROR] Archivo .env no encontrado en ${_SCRIPT_DIR}" >&2
    echo "[ERROR] Copiar .env.example como .env y completar las credenciales:" >&2
    echo "        cp .env.example .env" >&2
    exit 1
fi

source "$_ENV_FILE"

# =============================================================================
# Parámetros de exportación
# =============================================================================
MAIN_TABLE="plataforma_shared_vc"
MAIN_TABLE_PK="id_shared_vc"
MAIN_TABLE_LIMIT=500

OUTPUT_DIR="${_SCRIPT_DIR}/output"
ERROR_LOG="${OUTPUT_DIR}/logs/error_$(date +%d-%m-%Y).log"

# =============================================================================
# Binarios de PostgreSQL
# Ajustar si hay múltiples versiones instaladas (ej: servidor PG17, cliente PG12).
# También se pueden definir en .env para sobreescribir.
# =============================================================================
PSQL_BIN="${PSQL_BIN:-psql}"
PG_DUMP_BIN="${PG_DUMP_BIN:-pg_dump}"
PG_ISREADY_BIN="${PG_ISREADY_BIN:-pg_isready}"

# =============================================================================
# Tablas excluidas — no se exporta ningún dato
# =============================================================================
EXCLUDED_TABLES=(
    "log_auditoria"
    "auditoria"
    "log_desborde"
    "profesionales_log_estados"
    "requests_log"
)

# =============================================================================
# Tablas estáticas — se exportan completamente (datos de referencia/catálogo)
# =============================================================================
STATIC_TABLES=(
    "localidades"
    "municipio_ciudad_cod_postal_sires"
    "diagnosticos"
    "diagnosticos_idiomas"
    "practicas"
    "laboratorios"
    "universidades"
    "generos"
    "tipos_establecimiento_salud"
    "establecimientos_salud_sires"
    "farmalink_tamanos"
    "farmalink_vias"
    "translators_idiomas"
    "tipos_estados_generales_pacientes"
)
