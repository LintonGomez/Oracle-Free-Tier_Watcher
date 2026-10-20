# Contrato del motor de vigilancia

## Estado

Especificación de diseño para orientar la implementación compartida. No es una API implementada ni una validación ejecutada. Los nombres de tipos y estados son provisionales hasta que el código se desarrolle y revise.

## Responsabilidades

El motor coordina el flujo de vigilancia, pero no debe implementar directamente la terminal, el servicio de Windows, systemd, el almacenamiento de secretos ni detalles específicos de OCI. Depende de interfaces pequeñas que se puedan sustituir por dobles simulados en pruebas futuras.

## Configuración validada

La configuración debe convertirse en un objeto validado e inmutable antes de iniciar el ciclo:

- Región y compartment objetivo.
- Perfil de autenticación local o referencia al método de autenticación.
- Nombre objetivo de la instancia.
- Forma, OCPU, memoria y volumen de arranque.
- Imagen, subnet y clave pública SSH.
- Dominios de disponibilidad permitidos.
- Intervalos, timeouts y límites de reintento.
- Modo de simulación.
- Directorios locales de estado y registros.

Reglas:
- Rechazar valores ausentes, placeholders, tipos incorrectos y rangos inválidos.
- No imprimir el objeto completo de configuración en logs o errores.
- No almacenar material de clave privada en este objeto.
- Mantener separados los datos de autenticación y los parámetros de instancia.
- La configuración no debe permitir desactivar las protecciones contra ejecución concurrente o contra lanzamientos ante respuestas desconocidas.

## Interfaces conceptuales

### OciGateway

Operaciones mínimas:

- find_target_instances(config) -> InstanceLookupResult
- check_capacity(config, availability_domain) -> CapacityResult
- request_launch(config, availability_domain) -> LaunchResult

Los resultados deben ser tipos estructurados, no salida de consola sin procesar.

### StateStore

- acquire_lock() -> LockHandle
- read_state() -> WatcherState | None
- write_state_atomically(state) -> None

Debe escribir estado con permisos locales restrictivos y sin secretos. Un bloqueo ocupado significa que ya hay otra instancia del proceso; no se debe iniciar un segundo ciclo.

### SafeLogger

- info(event_code, safe_fields)
- warning(event_code, safe_fields)
- error(event_code, safe_fields)

Solo acepta códigos de evento y campos expresamente permitidos. No acepta ni imprime la salida cruda de OCI CLI, tokens, claves, OCID completos ni objetos de configuración enteros.

### Clock / WaitPolicy

El cálculo de reintentos debe estar aislado para poder ser revisado y posteriormente probado sin esperar en tiempo real. Debe limitar valores, añadir jitter acotado y usar una pausa larga o parada cuando el error no sea transitorio.

### ServiceAdapter

El motor recibe una señal de parada cancelable. Los adaptadores de Windows y Linux traducen la señal del sistema operativo en una solicitud de parada segura. El motor debe finalizar el ciclo actual de forma coherente y liberar el bloqueo.

## Tipos de resultado

### InstanceLookupResult

- FOUND: existe al menos una instancia no terminada que coincide con el criterio configurado.
- NOT_FOUND: la consulta fue válida y no se encontró instancia.
- ERROR: OCI rechazó la consulta, hubo timeout o el resultado no se pudo interpretar.

Solo NOT_FOUND permite avanzar a la consulta de capacidad. ERROR nunca se interpreta como ausencia de instancia.

### CapacityResult

- AVAILABLE: respuesta válida que confirma explícitamente disponibilidad para la forma solicitada.
- UNAVAILABLE: respuesta válida que confirma que no hay capacidad disponible.
- UNKNOWN: respuesta vacía, malformada, estado desconocido o esquema inesperado.
- THROTTLED: OCI limita la frecuencia de solicitudes.
- AUTH_ERROR: autenticación o autorización fallida.
- TRANSIENT_ERROR: error temporal de red/API.
- CONFIG_ERROR: parámetro o recurso inválido.

Solo AVAILABLE permite pasar al lanzamiento, y únicamente si la creación real fue habilitada explícitamente. Un estado desconocido nunca equivale a disponibilidad.

### LaunchResult

- ACCEPTED: OCI confirmó que aceptó la solicitud de creación.
- REJECTED_CAPACITY: el lanzamiento fue rechazado por falta de capacidad.
- THROTTLED: la API limitó la solicitud.
- AUTH_ERROR: falta de autenticación o permisos.
- CONFIG_ERROR: parámetros, cuotas o recursos no válidos.
- AMBIGUOUS: timeout o desconexión impiden saber si OCI aceptó la solicitud.
- TRANSIENT_ERROR: fallo con resultado no ambiguo y recuperable.

Un AMBIGUOUS obliga a volver a consultar instancias antes de considerar otra solicitud de creación. No reintentar inmediatamente.

## Máquina de estados

- STOPPED: sin actividad.
- VALIDATING_CONFIG: valida configuración local.
- ACQUIRING_LOCK: intenta evitar una segunda ejecución.
- CHECKING_INSTANCE: consulta instancias objetivo.
- CHECKING_CAPACITY: consulta cada dominio configurado.
- DRY_RUN_READY: hay capacidad, pero no se crearán recursos.
- LAUNCHING: envía una solicitud de creación autorizada.
- VERIFYING_AMBIGUOUS_LAUNCH: verifica si existe una instancia después de un resultado incierto.
- WAITING_RETRY: espera antes de un intento posterior.
- INSTANCE_FOUND: condición terminal; no crear otra instancia.
- LAUNCH_ACCEPTED: condición terminal para nuevos lanzamientos; se puede comprobar el estado sin emitir otra creación.
- NEEDS_ATTENTION: error no recuperable automáticamente o requiere intervención.
- STOPPING: finaliza el ciclo y libera recursos locales.

## Invariantes de seguridad

1. Nunca lanzar si la consulta de instancia no terminó con NOT_FOUND.
2. Nunca lanzar si el resultado de capacidad no es AVAILABLE.
3. Nunca lanzar si el modo de simulación está activado.
4. Nunca lanzar dos veces por una misma operación cuyo resultado sea ambiguo.
5. Nunca tratar un error de API como ausencia de instancia o capacidad disponible.
6. Nunca mantener un bucle agresivo ante autenticación, autorización, cuota o configuración inválida.
7. Nunca escribir credenciales ni respuestas crudas de OCI en logs o estado.
8. Nunca iniciar una segunda ejecución mientras el bloqueo esté adquirido.
9. La solicitud de parada del usuario impide iniciar nuevas operaciones de creación.
10. La desinstalación local nunca elimina recursos de OCI.

## Semántica de parada

El motor debe distinguir entre:
- Parada solicitada por el usuario: no iniciar más consultas o lanzamientos y cerrar de forma ordenada.
- Instancia objetivo encontrada: registrar un estado terminal y no emitir más lanzamientos.
- Solicitud de creación aceptada: no emitir otra creación automática.
- Error que requiere intervención: detener o pasar a una pausa larga y mostrar una explicación segura.
- Error temporal: reintentar únicamente según la política validada.

## CLI y servicios

La CLI y los adaptadores de servicio no deben implementar la lógica de capacidad. Solo deben construir configuración, invocar el motor, presentar estado y traducir órdenes de inicio/parada.

Los nombres de comandos previstos son provisionales:
- watcher configure
- watcher validate
- watcher status
- watcher logs --tail
- watcher service install
- watcher service start
- watcher service stop
- watcher service uninstall

## Validación pendiente

Antes de considerar estable el contrato:
- Revisar la documentación oficial vigente del API de capacidad de OCI y su esquema de respuesta.
- Implementar el motor y los tipos de resultado.
- Crear pruebas unitarias y dobles simulados de OCI.
- Revisar fallos de timeout, throttling, JSON malformado, instancia existente y resultados ambiguos de creación.
- Ejecutar comprobaciones estáticas y CI cuando estén disponibles.
- Validar los adaptadores de Windows y Linux en entornos controlados.
