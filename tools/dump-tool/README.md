# dump-tool

Herramienta para generar un dump reducido de la base de datos remota y restaurarlo en una base de datos local de desarrollo.

Evita descargar el dump completo obteniendo únicamente los datos necesarios, filtrados por brand, a partir de los últimos N registros de `plataforma_shared_vc` y todos los registros relacionados descubiertos automáticamente via claves foráneas.

---

## Uso rápido

```bash
# 1. Configurar credenciales (solo la primera vez)
cp .env.example .env
# editar .env con las credenciales reales

# 2. Verificar conectividad
./test_ssh.sh

# 3. Verificar esquema y grafo de FK (no toca datos)
./test_schema.sh

# 4. Exportar
./export.sh

# 5. Importar en la base local
./import.sh
```

---

## Requisitos previos

### Dependencias del sistema

- `ssh`
- `psql`, `pg_dump`, `pg_isready` — client tools de PostgreSQL **en la misma versión que el servidor remoto**

### Problema frecuente: incompatibilidad de versión de pg_dump

El servidor remoto corre PostgreSQL 17. Ubuntu 22.04 instala PG12 por defecto. Si las versiones no coinciden, `pg_dump` falla con:

```
pg_dump: error: versión del servidor: 17.4; versión de pg_dump: 12.x
```

**Solución: instalar postgresql-client-17**

```bash
sudo install -d /usr/share/postgresql-common/pgdg
sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail \
    https://www.postgresql.org/media/keys/ACCC4CF8.asc
sudo sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] \
    https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list'
sudo apt-get update
sudo apt-get install -y postgresql-client-17

# Verificar
/usr/lib/postgresql/17/bin/pg_dump --version
```

Luego descomentar en `.env`:

```bash
PSQL_BIN="/usr/lib/postgresql/17/bin/psql"
PG_DUMP_BIN="/usr/lib/postgresql/17/bin/pg_dump"
PG_ISREADY_BIN="/usr/lib/postgresql/17/bin/pg_isready"
```

---

## Configuración

Toda la configuración se hace en `.env` (gitignoreado). Copiar `.env.example` como punto de partida:

```bash
cp .env.example .env
```

### Variables requeridas

| Variable | Descripción |
|----------|-------------|
| `DB_NAME` | Nombre de la base remota |
| `DB_USER` | Usuario PostgreSQL remoto |
| `DB_PASSWORD` | Contraseña PostgreSQL remota |
| `DB_HOST` | Endpoint RDS (obtener desde AWS Console → RDS) |
| `DB_PORT` | Puerto PostgreSQL remoto (default: 5432) |
| `DB_SCHEMA` | Esquema PostgreSQL (default: portalsalud) |
| `SSH_USER` | Usuario del bastion EC2 |
| `SSH_HOST` | Host del bastion EC2 |
| `SSH_PRIVATE_KEY_PATH` | Ruta de la clave privada SSH, relativa a `$HOME` |
| `LOCAL_DB_NAME` | Nombre de la base local |
| `LOCAL_DB_USER` | Usuario PostgreSQL local |
| `LOCAL_DB_PASSWORD` | Contraseña PostgreSQL local |
| `BRAND` | ID del brand a exportar (entero) |

### Variables opcionales

| Variable | Descripción |
|----------|-------------|
| `LOCAL_PORT` | Puerto local del túnel (default: 3001) |
| `LOCAL_DB_HOST` | Host local (default: localhost) |
| `LOCAL_DB_PORT` | Puerto local (default: 5432) |
| `PSQL_BIN` | Ruta a psql (si hay múltiples versiones) |
| `PG_DUMP_BIN` | Ruta a pg_dump (si hay múltiples versiones) |
| `PG_ISREADY_BIN` | Ruta a pg_isready (si hay múltiples versiones) |

Los parámetros de exportación (`MAIN_TABLE`, `MAIN_TABLE_PK`, `MAIN_TABLE_LIMIT`) y las listas de tablas (`STATIC_TABLES`, `EXCLUDED_TABLES`) se configuran en `config.sh`.

---

## Scripts

### `export.sh` — Exportación completa

```bash
./export.sh
```

Ejecuta en orden:
1. Abre el túnel SSH
2. Verifica la conexión con la base remota
3. Descarga el esquema completo → `output/schema.sql`
4. Construye el grafo de FK → `output/dependency_graph.tsv`
5. Exporta tablas estáticas completas
6. Obtiene los últimos N registros de `plataforma_shared_vc` para el brand
7. Recorre el grafo BFS y exporta todos los registros relacionados → `output/data.sql`
8. Cierra el túnel SSH

---

### `import.sh` — Importación en base local

```bash
./import.sh
```

Requiere haber ejecutado `export.sh` previamente. La base local debe existir:

```bash
createdb -U postgres portalsalud_local
```

---

### `test_ssh.sh` — Prueba de conectividad

```bash
./test_ssh.sh
```

Abre el túnel, verifica `pg_isready` y ejecuta `SELECT version()`. Si funciona, el stack SSH → bastion → RDS está operativo.

---

### `test_schema.sh` — Prueba de esquema y grafo de FK

```bash
./test_schema.sh
```

Descarga el esquema y construye el grafo de dependencias. No toca datos de usuario — solo lee metadatos de `pg_catalog`. Útil para verificar la conexión y revisar las relaciones FK antes del export completo.

---

## Archivos generados en `output/`

| Archivo | Contenido |
|---------|-----------|
| `schema.sql` | DDL completo (estructura, índices, etc.) |
| `data.sql` | Datos reducidos en formato COPY |
| `dependency_graph.tsv` | Grafo FK: child\_table, child\_column, parent\_table, parent\_column |
| `main_ids.txt` | IDs exportados de `plataforma_shared_vc` |
| `error_DD-MM-YYYY.log` | Errores de pg_dump/psql (se limpia en cada ejecución) |

---

## Estructura del proyecto

```
dump-tool/
├── config.sh              Carga .env, define parámetros no sensibles y listas de tablas
├── export.sh              Script principal de exportación
├── import.sh              Script principal de importación
├── test_ssh.sh            Prueba de conectividad SSH y DB
├── test_schema.sh         Prueba de esquema y grafo de FK
│
├── lib/
│   ├── common.sh          Logging, init_error_log, show_error_log, check_dependencies
│   ├── ssh.sh             start_ssh_tunnel / verify_ssh_tunnel / stop_ssh_tunnel
│   ├── postgres.sh        _psql, _pg_dump, verify_connection, download_schema, export_table_data
│   ├── schema.sh          build_dependency_graph, get_children_of, print_graph_summary
│   └── reduced_dump.sh    export_static_tables, fetch_main_records, export_related (BFS)
│
├── sql/
│   ├── static_tables.sql  Documentación del criterio de tablas estáticas
│   ├── dynamic_queries.sql Consultas reutilizables
│   └── utils.sql          Consultas de diagnóstico y exploración
│
├── output/                Archivos generados (gitignoreado)
├── .env                   Credenciales reales (gitignoreado — NO commitear)
├── .env.example           Plantilla de credenciales (commitable)
├── .gitignore
└── notes.md               Notas del modelo de datos y volúmenes de tablas
```

---

## Resolución de problemas

### `localhost:XXXX - sin respuesta`

El túnel SSH abrió pero el RDS no responde. Causas posibles:
- El `DB_HOST` en `.env` es incorrecto. Obtener el endpoint real desde **AWS Console → RDS → la instancia → Endpoint**.
- El Security Group del RDS no permite conexiones desde el bastion en el puerto 5432.

Para diagnosticar desde el bastion:
```bash
ssh -i ~/<clave> <usuario>@<bastion> "nc -zv <DB_HOST> 5432"
```

### `password authentication failed for user "homestead"`

El `DB_USER` en `.env` está vacío. psql cae a la variable de entorno `PGUSER` del sistema (que en entornos Laravel/Homestead vale `homestead`). Verificar:

```bash
grep DB_USER .env
echo $PGUSER
```

### `pg_dump: error: versión del servidor no coincide`

Ver sección [Requisitos previos](#requisitos-previos).

### El túnel SSH ya está activo al iniciar

```
[WARN]  Ya existe un túnel SSH activo. Se reutiliza.
```

Normal — no es un error. El script detecta el túnel existente y lo reutiliza.

### `bind: Address already in use`

El puerto `LOCAL_PORT` está ocupado por un túnel anterior que no cerró limpiamente:

```bash
ssh -o ControlPath="/tmp/dump-tool-*" -O exit <SSH_USER>@<SSH_HOST>
```
