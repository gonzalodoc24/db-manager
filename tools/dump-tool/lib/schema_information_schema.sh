#!/bin/bash

# =============================================================================
# Grafo de dependencias entre tablas
#
# El grafo se construye automáticamente a partir de las claves foráneas del
# esquema de PostgreSQL, usando information_schema.
#
# Formato del archivo de grafo (TSV, una FK por línea):
#   child_table <TAB> child_column <TAB> parent_table <TAB> parent_column
#
# "child" es la tabla que tiene la FK; "parent" es la tabla referenciada.
# Ejemplo:
#   consultas_virtuales  id_plataforma_shared_vc  plataforma_shared_vc  id
#   atenciones           id_consulta              consultas_virtuales   id
# =============================================================================

GRAPH_FILE="${OUTPUT_DIR}/dependency_graph.tsv"

# Consulta information_schema y genera el archivo de grafo.
build_dependency_graph() {
    log_step "Construyendo grafo de dependencias desde claves foráneas..."

    mkdir -p "$OUTPUT_DIR"

    local sql="
SELECT
    tc.table_name        AS child_table,
    kcu.column_name      AS child_column,
    ccu.table_name       AS parent_table,
    ccu.column_name      AS parent_column
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
   AND tc.table_schema    = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
   AND ccu.table_schema    = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema    = '${DB_SCHEMA}'
ORDER BY tc.table_name, kcu.column_name;
"

    _psql -t -A -F $'\t' -c "$sql" > "$GRAPH_FILE"

    local count
    count=$(wc -l < "$GRAPH_FILE")
    log_success "Grafo construido: ${count} relaciones FK encontradas."
    log_info "Grafo guardado en: $GRAPH_FILE"
}

# Devuelve todas las tablas "hijo" que tienen una FK apuntando a parent_table.
# Cada línea del resultado: child_table <TAB> child_column <TAB> parent_table <TAB> parent_column
get_children_of() {
    local parent_table="$1"
    awk -F'\t' -v pt="$parent_table" '$3 == pt { print }' "$GRAPH_FILE" 2>/dev/null
}

# Devuelve todas las tablas "padre" que child_table referencia.
get_parents_of() {
    local child_table="$1"
    awk -F'\t' -v ct="$child_table" '$1 == ct { print }' "$GRAPH_FILE" 2>/dev/null
}

# Imprime un resumen legible del grafo de dependencias centrado en una tabla.
# Muestra el árbol de relaciones hasta depth niveles de profundidad.
print_dependency_tree() {
    local root_table="${1:-$MAIN_TABLE}"
    local depth="${2:-3}"
    local indent="${3:-}"

    echo "${indent}${root_table}"

    if [[ $depth -le 0 ]]; then
        return
    fi

    while IFS=$'\t' read -r child_table child_column parent_table parent_column; do
        echo "${indent}  └── ${child_table} (${child_column} → ${parent_column})"
        print_dependency_tree "$child_table" $((depth - 1)) "${indent}      "
    done < <(get_children_of "$root_table")
}

# Imprime todas las relaciones FK del grafo en formato legible.
print_graph_summary() {
    log_info "Relaciones FK del esquema ${DB_SCHEMA}:"
    echo ""
    echo "  child_table.child_column → parent_table.parent_column"
    echo "  --------------------------------------------------------"
    while IFS=$'\t' read -r child_table child_column parent_table parent_column; do
        printf "  %-45s → %s.%s\n" "${child_table}.${child_column}" "$parent_table" "$parent_column"
    done < "$GRAPH_FILE"
    echo ""
}
