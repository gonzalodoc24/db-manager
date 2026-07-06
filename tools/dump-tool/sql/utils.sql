-- =============================================================================
-- Consultas utilitarias para diagnóstico y exploración
-- =============================================================================


-- Tamaño promedio en bytes de un registro en una muestra limitada
SELECT AVG(pg_column_size(t.*)) AS avg_row_size
FROM (SELECT * FROM portalsalud.atenciones LIMIT 1000) t;


-- Tamaño aproximado en bytes de X registros (X = 10000)
SELECT AVG(pg_column_size(t.*)) * 10000 AS approx_size_for_10000_rows
FROM (SELECT * FROM portalsalud.atenciones LIMIT 1000) t;


-- Contar registros por brand en plataforma_shared_vc
SELECT brand, COUNT(*) AS total
FROM portalsalud.plataforma_shared_vc
GROUP BY brand
ORDER BY total DESC;


-- Ver los últimos registros de plataforma_shared_vc para un brand
SELECT *
FROM portalsalud.plataforma_shared_vc
WHERE brand = 31
ORDER BY id_shared_vc DESC
LIMIT 10;


-- Ver todas las tablas con columna brand y su conteo para un brand específico
-- (requiere ejecutarse tabla por tabla)
SELECT COUNT(*) FROM portalsalud.consultas_virtuales WHERE brand = 31;


-- Verificar FK de plataforma_shared_vc hacia consultas_virtuales
SELECT psv.id_shared_vc, psv.id_consulta_virtual, cv.id_consulta_virtual
FROM portalsalud.plataforma_shared_vc psv
LEFT JOIN portalsalud.consultas_virtuales cv
    ON psv.id_consulta_virtual = cv.id_consulta_virtual
WHERE psv.brand = 31
ORDER BY psv.id_shared_vc DESC
LIMIT 10;
