#!/bin/bash

# =============================================================================
# Generación del dump reducido
#
# Estrategia:
#   1. Exportar tablas estáticas (referencia/catálogo) completas.
#   2. Obtener los últimos N registros de plataforma_shared_vc para el brand.
#   3. Recorrer el grafo de dependencias en BFS para exportar todos los
#      registros relacionados, garantizando consistencia referencial.
#
# Limitación conocida: si una tabla es alcanzable por múltiples caminos en el
# grafo, solo se exporta por el primer camino encontrado. Las IDs del segundo
# camino se ignoran. Esto es aceptable para un dump de desarrollo.
# =============================================================================

MAIN_IDS_FILE="${OUTPUT_DIR}/main_ids.txt"
DATA_FILE="${OUTPUT_DIR}/data.sql"

# Tablas ya procesadas en esta ejecución (evita ciclos y doble exportación).
declare -A _VISITED_TABLES

_is_visited() { [[ -n "${_VISITED_TABLES[$1]+x}" ]]; }
_mark_visited() { _VISITED_TABLES["$1"]=1; }

# --------------------------------------------------------------------------
# Paso 1: Tablas estáticas
# --------------------------------------------------------------------------
export_static_tables() {
    log_step "Exportando tablas estáticas..."
    for table in "${STATIC_TABLES[@]}"; do
        if _is_visited "$table"; then
            continue
        fi
        log_info "  → ${table} (completa)"
        export_table_data "$table" "" "$DATA_FILE"
        _mark_visited "$table"
    done
}

# --------------------------------------------------------------------------
# Paso 2: Registros principales de plataforma_shared_vc
# --------------------------------------------------------------------------
fetch_main_records() {
    log_step "Obteniendo últimos ${MAIN_TABLE_LIMIT} registros de ${MAIN_TABLE} para brand=${BRAND}..."

    run_sql "
SELECT ${MAIN_TABLE_PK}
FROM ${DB_SCHEMA}.${MAIN_TABLE}
WHERE brand = ${BRAND}
ORDER BY ${MAIN_TABLE_PK} DESC
LIMIT ${MAIN_TABLE_LIMIT};
" > "$MAIN_IDS_FILE"

    local count
    count=$(grep -c . "$MAIN_IDS_FILE" || echo 0)

    [[ $count -gt 0 ]] || die "No se encontraron registros en ${MAIN_TABLE} para brand=${BRAND}."
    log_success "Encontrados ${count} registros en ${MAIN_TABLE}."
}

# --------------------------------------------------------------------------
# Paso 3 y 4: Recorrido del grafo de dependencias (BFS)
#
# export_related <parent_table> <csv_ids>
#   parent_table: nombre de la tabla padre
#   csv_ids:      IDs de los registros del padre, en formato CSV (1,2,3,...)
#
# Para cada tabla hijo que referencie a parent_table:
#   - Exporta los registros del hijo que apuntan a esos IDs.
#   - Obtiene los IDs del hijo para seguir recorriendo el grafo.
# --------------------------------------------------------------------------
export_related() {
    local parent_table="$1"
    local parent_ids_csv="$2"

    [[ -n "$parent_ids_csv" ]] || return 0

    local children
    children=$(get_children_of "$parent_table")

    [[ -n "$children" ]] || return 0

    while IFS=$'\t' read -r child_table child_column _parent_table parent_column; do
        if _is_visited "$child_table"; then
            log_info "  ↷ ${child_table} (ya exportada, omitiendo)"
            continue
        fi

        # Columna PK del hijo para obtener sus IDs y continuar el recorrido.
        local child_pk
        child_pk=$(get_primary_key "$child_table")
        if [[ -z "$child_pk" ]]; then
            log_warn "  Sin PK detectada en ${child_table}, exportando sin recursión."
            export_table_data "$child_table" "WHERE ${child_column} IN (${parent_ids_csv})" "$DATA_FILE"
            _mark_visited "$child_table"
            continue
        fi

        # Obtener IDs del hijo antes de exportar para no leer datos del archivo a medias.
        local child_ids_raw
        child_ids_raw=$(run_sql "
SELECT ${child_pk}
FROM ${DB_SCHEMA}.${child_table}
WHERE ${child_column} IN (${parent_ids_csv});
")

        if [[ -z "$child_ids_raw" ]]; then
            log_info "  → ${child_table}: sin registros relacionados"
            _mark_visited "$child_table"
            continue
        fi

        local child_ids_csv
        child_ids_csv=$(echo "$child_ids_raw" | paste -sd',')

        local child_count
        child_count=$(echo "$child_ids_raw" | wc -l | tr -d ' ')

        log_info "  → ${child_table} (${child_count} registros, via ${child_column})"
        export_table_data "$child_table" "WHERE ${child_column} IN (${parent_ids_csv})" "$DATA_FILE"
        _mark_visited "$child_table"

        # Recursión: explorar los hijos del hijo.
        export_related "$child_table" "$child_ids_csv"

    done <<< "$children"
}

# --------------------------------------------------------------------------
# Orquestador principal
# --------------------------------------------------------------------------
generate_reduced_dump() {
    mkdir -p "$OUTPUT_DIR"
    > "$DATA_FILE"

    {
        echo "-- Dump reducido generado por dump-tool"
        echo "-- Brand ID: ${BRAND}"
        echo "-- Tabla principal: ${MAIN_TABLE} (últimos ${MAIN_TABLE_LIMIT} registros)"
        echo ""
        echo "SET session_replication_role = replica;"
        echo ""
    } >> "$DATA_FILE"

    # Paso 1
    export_static_tables

    # Paso 2
    fetch_main_records

    local main_ids_csv
    main_ids_csv=$(cat "$MAIN_IDS_FILE" | paste -sd',')

    # Exportar tabla principal
    log_step "Exportando registros de ${MAIN_TABLE}..."
    export_table_data "$MAIN_TABLE" "WHERE ${MAIN_TABLE_PK} IN (${main_ids_csv})" "$DATA_FILE"
    _mark_visited "$MAIN_TABLE"

    # Paso 3 y 4: recorrer grafo
    log_step "Exportando registros relacionados via grafo de dependencias..."
    export_related "$MAIN_TABLE" "$main_ids_csv"

    echo "" >> "$DATA_FILE"
    echo "SET session_replication_role = DEFAULT;" >> "$DATA_FILE"

    log_success "Dump reducido guardado en: $DATA_FILE"
}
