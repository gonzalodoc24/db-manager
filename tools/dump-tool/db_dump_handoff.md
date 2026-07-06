# Handoff - Herramienta para generar un dump reducido de PostgreSQL

## Objetivo

Desarrollar una herramienta en Bash que permita generar un dump reducido de la base de datos remota para poder restaurarlo rápidamente en una base de datos local.

La conexión a la base remota se realiza mediante un túnel SSH.

El objetivo es evitar descargar un dump completo (muy pesado) y obtener únicamente la información necesaria para poder desarrollar localmente.

---

# Estado actual

La herramienta fue reorganizada y modularizada en `database/scripts/dump-tool/`.

```
dump-tool/
├── config.sh              Carga el .env y define parámetros no sensibles
├── export.sh              Script principal de exportación
├── import.sh              Script principal de importación
├── test_ssh.sh            Prueba de conectividad SSH y DB
├── test_schema.sh         Prueba de descarga de esquema y grafo de FK
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
├── output/                Archivos generados (gitignoreado)
├── .env                   Credenciales reales (gitignoreado, NO commitear)
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
- `.env` contiene las credenciales reales y está gitignoreado.
- `.env.example` es la plantilla commitable.

## Logging de errores

- Stderr de `pg_dump` y `psql` se redirige a `output/error_DD-MM-YYYY.log`.
- En caso de error se muestran solo las primeras 5 líneas truncadas a 120 caracteres.
- El log se limpia al inicio de cada ejecución.

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
| Scripts de prueba (test_ssh, test_schema) | ✅ Completado |
| Probar export.sh end-to-end | 🔲 Pendiente |
| Probar import.sh end-to-end | 🔲 Pendiente |
| Validar consistencia del dump generado | 🔲 Pendiente |

---

# Próximos pasos

1. Verificar conectividad con el endpoint correcto del RDS (ver `tools/aws/aws_servers_info.md`).
2. Ejecutar `./test_schema.sh` para confirmar que el esquema se descarga y el grafo se construye.
3. Ejecutar `./export.sh` y revisar los archivos generados en `output/`.
4. Crear la base local e importar con `./import.sh`.
5. Validar que los datos importados son consistentes (sin FK violations).

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
