#!/bin/bash

# =============================================================================
# Funciones auxiliares de PostgreSQL
# Todas las conexiones se realizan a través del túnel SSH (localhost:LOCAL_PORT).
# =============================================================================

_psql() {
    PGPASSWORD="${DB_PASSWORD}" "${PSQL_BIN}" \
        -h "localhost" \
        -p "${LOCAL_PORT}" \
        -U "${DB_USER}" \
        -d "${DB_NAME}" \
        "$@" 2>>"${ERROR_LOG}"
}

_pg_dump() {
    PGPASSWORD="${DB_PASSWORD}" "${PG_DUMP_BIN}" \
        -h "localhost" \
        -p "${LOCAL_PORT}" \
        -U "${DB_USER}" \
        -d "${DB_NAME}" \
        "$@" 2>>"${ERROR_LOG}"
}

# Ejecuta una query SQL y devuelve el resultado en formato plano (una columna por línea).
run_sql() {
    local sql="$1"
    _psql -t -A -c "$sql"
}

# Ejecuta un archivo SQL.
run_sql_file() {
    local file="$1"
    _psql -f "$file"
}

# Verifica que la conexión con la base de datos sea exitosa.
verify_connection() {
    log_info "Verificando conexión con la base de datos..."
    PGPASSWORD="${DB_PASSWORD}" "${PG_ISREADY_BIN}" \
        -h "localhost" \
        -p "${LOCAL_PORT}" \
        -U "${DB_USER}" \
        -d "${DB_NAME}" \
        -t 10 2>>"${ERROR_LOG}"

    if [[ $? -ne 0 ]]; then
        show_error_log
        die "No se puede conectar a la base de datos. Verificar configuración."
    fi
    log_success "Conexión OK."
}

# Descarga el esquema completo de la base remota.
download_schema() {
    local output_file="$1"
    log_step "Descargando esquema de la base de datos..."

    if ! _pg_dump \
        --schema="${DB_SCHEMA}" \
        --schema-only \
        --no-owner \
        --no-acl \
        --encoding=utf-8 \
        -f "$output_file"; then
        show_error_log
        die "Error descargando el esquema."
    fi

    log_success "Esquema guardado en: $output_file"
}

# Exporta los datos de una tabla en formato COPY (compatible con psql).
# Escribe un bloque COPY ... FROM stdin; ... \. en el archivo de destino.
export_table_data() {
    local table="$1"
    local where_clause="${2:-}"
    local output_file="$3"
    local full_table="${DB_SCHEMA}.${table}"

    {
        echo ""
        echo "-- ${full_table}"
        echo "COPY ${full_table} FROM stdin;"
        _psql -t -A -c "COPY (SELECT * FROM ${full_table} ${where_clause}) TO STDOUT;"
        echo "\."
    } >> "$output_file"

    if [[ $? -ne 0 ]]; then
        show_error_log
        log_error "Error exportando datos de: $table"
        return 1
    fi
}

# Obtiene la columna de clave primaria de una tabla.
get_primary_key() {
    local table="$1"
    run_sql "
SELECT kcu.column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
   AND tc.table_schema    = kcu.table_schema
WHERE tc.constraint_type = 'PRIMARY KEY'
  AND tc.table_schema    = '${DB_SCHEMA}'
  AND tc.table_name      = '${table}'
ORDER BY kcu.ordinal_position
LIMIT 1;
"
}
