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

# Construye el grafo consultando pg_catalog directamente.
# Más rápido que information_schema (~150x) y más completo (sin filtros de permisos por columna).
# Benchmark: information_schema=977ms/38 filas vs pg_catalog=6.8ms/200 filas.
build_dependency_graph() {
    log_step "Construyendo grafo de dependencias desde claves foráneas..."

    mkdir -p "$OUTPUT_DIR"

    local sql="
SELECT
    child_rel.relname  AS child_table,
    child_att.attname  AS child_column,
    parent_rel.relname AS parent_table,
    parent_att.attname AS parent_column
FROM pg_constraint con
JOIN pg_class     child_rel  ON child_rel.oid  = con.conrelid
JOIN pg_class     parent_rel ON parent_rel.oid = con.confrelid
JOIN pg_namespace ns         ON ns.oid         = child_rel.relnamespace
JOIN pg_attribute child_att
    ON child_att.attrelid = con.conrelid
   AND child_att.attnum   = ANY(con.conkey)
JOIN pg_attribute parent_att
    ON parent_att.attrelid = con.confrelid
   AND parent_att.attnum   = ANY(con.confkey)
WHERE con.contype = 'f'
  AND ns.nspname  = '${DB_SCHEMA}'
ORDER BY child_rel.relname, child_att.attname;
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
