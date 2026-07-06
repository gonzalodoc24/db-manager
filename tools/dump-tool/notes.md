# Notas del modelo de datos

Migrado y actualizado desde el proyecto anterior.

---

## Tablas por volumen de datos (base test)

### Tablas MUY grandes (requieren filtrado)

```
atenciones                              ~52k registros en test, ~50M en prod
consultas_virtuales
farmalink_manextra
usuarios_tyc_aceptados
clave_maestra_paciente_solicitudes
external_login_requests
productos_no_alfabeta
plataforma_shared_vc_clicks
plataforma_shared_vc                    tabla principal del dump reducido
diagnosticos
localidades                             NO limitar — tabla de referencia
diagnosticos_idiomas
consultorios_financiadores
plataforma_afiliaciones_upcnba
municipio_ciudad_cod_postal_sires       NO limitar — tabla de referencia
plataforma_afiliaciones_default
requests_log                            IGNORAR
log_desborde                            IGNORAR (~1M registros)
consultorios_programados_turnos         ~5M registros, 2GB en test
```

### Tablas grandes

```
plataforma_localidades_brands           ~12k registros, 1.5MB
establecimientos_salud_sires            ~15k registros, 2.5MB
plataforma_vauchers
usuarios_tokens
external_studies
plataforma_shared_vc_triage_respuestas
documentos_generados
profesionales_guardia
consultas_respuestas_cuestionario
plataforma_registro_actividad
atenciones_diagnosticos_presuntivos
practicas
phr_eventos                             ~30k registros, 3.3MB
form_response
usuarios                                ~30k registros, 6.5MB
consultas_cancelaciones                 ~35k registros, 19MB
phr                                     ~25k registros, 4.7MB
personas
credenciales_usuarios
claims
cobertura_alfabeta_brands
consultas_virtuales_users_agents
consultas_virtuales_posiciones_informadas
farmalink_manual                        ~49k registros, 10MB
```

### Tablas irrelevantes (excluidas)

No son necesarias para desarrollo:

```
log_auditoria                           ~25k registros, 9MB
log_desborde                            ~1M registros
auditoria                               >60M registros
profesionales_log_estados
requests_log
```

### Tablas con cero registros en test

```
atenciones_files
atenciones_interconsultas
atenciones_sugerencias_interconsultas
atenciones_tipos_protocolos_seguimiento
auditoria_new
claims_eventos
clave_maestra_paciente
clave_maestra_paciente_personas
codigos_descuentos_externos
consultas_domiciliarias
consultas_liberaciones
consultas_virtuales_auditoria_ubicacion
consultas_virtuales_claims
consultas_virtuales_notificaciones_actividad
consultas_virtuales_tarifas_pacientes
consultorios_diagnosticos
consultorios_disponibles
consultorios_guardia_brand
consultorios_parametros_generales
consultorios_practicas
consultorios_tipos_especialidades_codigo_prestador
consultorios_tipos_especialidades_demoras
consultorios_ubicaciones
convenios_mensuales_plataforma_financiadores
convenios_plataforma_prestadores
default_montos_prestadores
documentos_generados_validaciones
estados
facturacion_financiadores
facturacion_liquidaciones
facturacion_pacientes_particular
facturacion_prestadores
farmalink_tamanos
farmalink_vias
generos
laboratorios
notificaciones_profesionales
nps_mercado_libre
persistencia_id_ambientes
personas_canales_contacto
personas_domicilios
personas_pago_electronico
personas_raza
personas_urgencias
phr_atenciones
phr_estudios
phr_estudios_adjuntos
phr_eventos_adjuntos
phr_laboratorios
phr_laboratorios_adjuntos
phr_laboratorios_determinaciones
plataforma_administradores
plataforma_afiliaciones_amupap
plataforma_afiliaciones_cliente
plataforma_afiliaciones_cliente_pagos
plataforma_afiliaciones_mylatindoc
plataforma_afiliaciones_mylatindoc_pago
plataforma_brands_deeplinks
plataforma_brands_firebase
plataforma_brands_micrositios
plataforma_brands_versiones
plataforma_ip_whitelist
plataforma_iss_allowed_methods
plataforma_shared_vc_ack_errores
plataforma_uf
plataforma_user_profile_allowed_methods
practicas_entidades_sugeridas
prestadores_autorizaciones
prestadores_canales_contacto
prestadores_consumo_diario
prestadores_pagos
prestadores_terceros
prestadores_usuarios
prestadores_usuarios_tokens
profesionales_firma
profesionales_log_estados
puntos_venta
puntos_venta_campanias
puntos_venta_links
puntos_venta_transacciones
seguimiento_cronicos_pacientes_especialidades_crm
seguimiento_cronicos_pacientes_especialidades_turnos
sesiones_multiples_grupos_profesionales
sesiones_tb_consultorios
talleres_multisesion
tipos_establecimiento_salud
tipos_estados_generales_pacientes
translators_idiomas
universidades
usuarios_cuarentena
usuarios_empresas
usuarios_perfiles
usuarios_ubicaciones
vademecun_consultorios
vademecun_financiadores
vademecun_laboratorios_farmaceuticos
```

---

## Conexión a la base

Para evitar que psql pida credenciales en cada ejecución:

```bash
echo "host:port:database:username:password" >> ~/.pgpass
chmod 600 ~/.pgpass
```

---

## Árbol de dependencias esperado (referencia)

```
plataforma_shared_vc
        │
        ├── consultas_virtuales
        │         │
        │         ├── atenciones
        │         │      ├── personas
        │         │      ├── profesionales
        │         │      ├── recetas
        │         │      └── ...
        │         │
        │         └── consultas_chat
        │                 └── mensajes
        │
        └── ...
```

Este árbol se genera automáticamente via `build_dependency_graph` en `lib/schema.sh`.
Para visualizarlo ejecutar `print_dependency_tree` desde export.sh.
