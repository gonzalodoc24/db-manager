# Handoff - Herramienta para generar un dump reducido de PostgreSQL

## Objetivo

Desarrollar una herramienta en Bash que permita generar un dump reducido de la base de datos remota para poder restaurarlo rápidamente en una base de datos local.

La conexión a la base remota se realiza mediante un túnel SSH.

El objetivo es evitar descargar un dump completo (muy pesado) y obtener únicamente la información necesaria para poder desarrollar localmente.

---

# Estado actual

La herramienta fue reorganizada y modularizada en `tools/dump-tool/`.

```
dump-tool/
├── config.sh              Carga el .env y define parámetros no sensibles
├── export.sh              Script principal de exportación
├── import.sh              Script principal de importación
├── connection.sh          Prueba de conectividad SSH y DB
│
├── lib/
│   ├── common.sh          Logging, init_error_log, show_error_log
│   ├── ssh.sh             start/verify/stop túnel SSH (via ControlMaster)
│   ├── postgres.sh        _psql, _pg_dump, verify_connection, download_schema, export_table_data
│   ├── schema.sh          build_dependency_graph, get_children_of, print_graph_summary
│   └── reduced_dump.sh    export_static_tables, fetch_main_records, export_related (BFS)
│
├── sql/
│   ├── static_tables.sql  Documentación del criterio de tablas estáticas
│   ├── dynamic_queries.sql Consultas reutilizables (FK graph, tamaños, etc.)
│   └── utils.sql          Consultas de diagnóstico
│
├── output/                Archivos generados (ignorado en git)
├── .env                   Credenciales reales (ignorado en git, NO commitear)
├── .env.example           Plantilla de credenciales (commitable)
├── .gitignore             Ignora .env y output/*
├── notes.md               Notas del modelo de datos
└── README.md              Documentación completa de uso
```

---

# Decisiones tomadas durante el desarrollo

## Modelo de datos

- La PK de `plataforma_shared_vc` es `id_shared_vc` (no `id`).
- La columna `brand` es un **entero** (FK a tabla de brands), no un string.
- La relación principal es: `plataforma_shared_vc.id_consulta_virtual → consultas_virtuales.id_consulta_virtual`.

## Grafo de dependencias

Se optó por consultar `pg_catalog` directamente en lugar de `information_schema`:

- `information_schema`: 977ms, devolvía 38 FKs (filtraba por permisos de columna).
- `pg_catalog`: 6.8ms, devuelve 200 FKs (resultado completo y correcto).

La query está en `lib/schema.sh` (`build_dependency_graph`). La versión original con `information_schema` quedó preservada en `lib/schema_information_schema.sh`.

## Credenciales

Se implementó el patrón `.env`:
- `config.sh` es commitable y no contiene credenciales.
- `.env` contiene las credenciales reales.
- `.env.example` es la plantilla commitable.

## Logging de errores

- Stderr de `pg_dump` y `psql` se redirige a `output/logs/error_DD-MM-YYYY.log`.
- En caso de error se muestran solo las primeras 5 líneas truncadas a 120 caracteres.
- El log se limpia al inicio de cada ejecución.

## Flags de `export.sh`

Para evitar rehacer pasos costosos durante la iteración de pruebas (ej: no re-descargar el esquema completo si no cambió), `export.sh` soporta:

- `--skip-schema` / `--skip-graph`: reutilizan `output/schema.sql` / `output/dependency_graph.tsv` existentes en vez de regenerarlos.
- `--only-schema` / `--only-graph`: cortan la ejecución justo después de ese paso, sin llegar a exportar datos.

Estos flags reemplazan a `test_schema.sh` (eliminado): antes era un script aparte para probar solo esquema+grafo, ahora es el mismo `export.sh` con flags. Ver detalle y combinaciones en `README.md`.

## Flags de `import.sh`

- `--skip-schema`: omite la importación del esquema (asume que ya existe) y va directo a los datos.
- `--only-schema`: importa solo el esquema y termina.
- `--drop-schema`: como `schema.sql` genera `CREATE SCHEMA ${DB_SCHEMA};` sin `DROP`/`IF NOT EXISTS`, reimportar sobre una base que ya tiene el esquema falla con "already exists". Este flag corre `DROP SCHEMA IF EXISTS ${LOCAL_DB_SCHEMA} CASCADE;` antes de importar. Requiere la variable `LOCAL_DB_SCHEMA` en `.env`. Es destructivo (borra todo el esquema local) — usar con cuidado.
- `--drop-schema` y `--skip-schema` son excluyentes.

La importación de esquema y de datos usa `psql -q` para no volcar en consola cada `ALTER TABLE` / `COPY N` del dump.

## Binarios de PostgreSQL

El servidor remoto corre PostgreSQL 17. Ubuntu 22.04 instala PG12 por defecto.
Se agregó soporte para configurar la ruta de los binarios via `.env`:

```bash
PSQL_BIN="/usr/lib/postgresql/17/bin/psql"
PG_DUMP_BIN="/usr/lib/postgresql/17/bin/pg_dump"
PG_ISREADY_BIN="/usr/lib/postgresql/17/bin/pg_isready"
```

Instalación: ver sección "Requisitos previos" en `README.md`.

---

# Progreso

| Tarea | Estado |
|-------|--------|
| Reorganizar estructura modular | ✅ Completado |
| Encapsular túnel SSH | ✅ Completado |
| Descargar esquema completo | ✅ Completado |
| Construir grafo de dependencias desde FK | ✅ Completado |
| Exportar tablas estáticas | ✅ Completado |
| Exportar tabla principal filtrada por brand | ✅ Completado |
| Recorrer grafo BFS y exportar relacionados | ✅ Completado |
| Script de importación local | ✅ Completado |
| Patrón .env para credenciales | ✅ Completado |
| Error logging con fecha | ✅ Completado |
| Script de prueba de conectividad (connection.sh) | ✅ Completado |
| Flags --skip-schema/--skip-graph/--only-schema/--only-graph en export.sh | ✅ Completado |
| Flags --skip-schema/--only-schema/--drop-schema en import.sh | ✅ Completado |
| Probar export.sh end-to-end | ✅ Completado |
| Probar import.sh end-to-end | ✅ Completado (con `--only-schema`; falta correr el dump de datos completo) |
| Validar consistencia del dump generado | 🔲 Pendiente |

---

# Próximos pasos

1. Ejecutar `./import.sh --drop-schema` completo (esquema + datos) contra la base local `portalsalud`.
2. Validar que los datos importados son consistentes (sin FK violations) — ver sección "Consideraciones pendientes".
3. Evaluar si hace falta cubrir el caso de tablas con `brand` no alcanzables desde `plataforma_shared_vc`.

---

# Consideraciones pendientes

## Tablas con brand sin FK hacia plataforma_shared_vc

Toda tabla que tenga columna `brand` pero no sea alcanzable desde `plataforma_shared_vc` via el grafo de FK **no se exportará automáticamente**. Evaluar si hace falta un mecanismo adicional para exportar estas tablas filtradas por brand.

## Tablas alcanzables por múltiples caminos

Si una tabla es alcanzable desde `plataforma_shared_vc` por dos caminos distintos en el grafo, solo se exporta por el primer camino encontrado (BFS). Los registros del segundo camino se ignoran. Documentado en `lib/reduced_dump.sh`. Aceptable para desarrollo.

---

# Arquitectura de referencia

```
dump-tool/
        │
        ├── export.sh ──────────────────────────────────────────────────────┐
        │    │                                                               │
        │    ├── lib/ssh.sh          → abre/cierra túnel SSH                │
        │    ├── lib/postgres.sh     → verify_connection, download_schema   │
        │    ├── lib/schema.sh       → build_dependency_graph               │
        │    └── lib/reduced_dump.sh → generate_reduced_dump (BFS)          │
        │                                                                    │
        └── import.sh ───────────────────────────────────────────────────── ┘
             │
             └── psql -f schema.sql && psql -f data.sql
```

---

# Estrategia para generar el dump reducido

## 1. Excluir tablas

```
log_auditoria, auditoria, log_desborde, profesionales_log_estados, requests_log
```

## 2. Tablas estáticas

Exportar completamente (sin filtro de brand). Configuradas en `config.sh` (`STATIC_TABLES`).

## 3. Filtrar por Brand

`BRAND` se configura en `.env` como entero. Toda tabla con columna `brand` se filtra por ese valor.

## 4. Tabla principal

`plataforma_shared_vc` — últimos `MAIN_TABLE_LIMIT` registros ordenados por `id_shared_vc DESC` para el brand seleccionado.

## 5. Recuperación de datos relacionados

Recorrido BFS del grafo de FK a partir de `plataforma_shared_vc`. El grafo se construye automáticamente desde `pg_catalog` al inicio de cada exportación.
