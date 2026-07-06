-- =============================================================================
-- Consultas dinámicas utilizadas durante la exportación
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Grafo de dependencias: todas las FK del esquema
-- Reemplazar :schema con el nombre del esquema (ej: portalsalud)
-- -----------------------------------------------------------------------------
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
  AND tc.table_schema    = :'schema'
ORDER BY tc.table_name, kcu.column_name;


-- -----------------------------------------------------------------------------
-- Claves primarias de todas las tablas del esquema
-- -----------------------------------------------------------------------------
SELECT
    tc.table_name,
    kcu.column_name AS pk_column
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
   AND tc.table_schema    = kcu.table_schema
WHERE tc.constraint_type = 'PRIMARY KEY'
  AND tc.table_schema    = :'schema'
ORDER BY tc.table_name, kcu.ordinal_position;


-- -----------------------------------------------------------------------------
-- Registros principales: últimos N de plataforma_shared_vc para un brand
-- Reemplazar :brand (entero) y :limit
-- -----------------------------------------------------------------------------
SELECT id_shared_vc
FROM portalsalud.plataforma_shared_vc
WHERE brand = :brand
ORDER BY id_shared_vc DESC
LIMIT :limit;


-- -----------------------------------------------------------------------------
-- Tablas con columna brand en el esquema
-- -----------------------------------------------------------------------------
SELECT DISTINCT table_name
FROM information_schema.columns
WHERE table_schema  = :'schema'
  AND column_name   = 'brand'
ORDER BY table_name;


-- -----------------------------------------------------------------------------
-- Tamaño aproximado de tablas en el esquema (para diagnóstico)
-- -----------------------------------------------------------------------------
SELECT
    relname                                          AS table_name,
    n_live_tup                                       AS row_count,
    pg_size_pretty(pg_total_relation_size(relid))    AS total_size
FROM pg_stat_user_tables
WHERE schemaname = :'schema'
ORDER BY pg_total_relation_size(relid) DESC;
