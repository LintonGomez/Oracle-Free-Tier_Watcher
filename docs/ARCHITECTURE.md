# Arquitectura propuesta: Windows y Linux

## Estado del documento

Diseño técnico, no implementación validada. No se han ejecutado pruebas ni se debe interpretar este diseño como garantía de compatibilidad. La ejecución de validaciones queda pendiente de disponer de un runner y cuota de GitHub Actions.

## Objetivo

Distribuir una aplicación local que consulte OCI directamente y, si el usuario lo habilita, intente crear una instancia cuando la API confirme capacidad disponible. No requiere backend, cuenta del proyecto, telemetría ni servicio central.

## Separación de componentes

La implementación multiplataforma debe separar cuatro responsabilidades:

1. **Motor de dominio**: máquina de estados, política de reintentos, reconocimiento de instancia objetivo y reglas para evitar duplicados.
2. **Adaptador OCI**: ejecuta operaciones OCI mediante el OCI CLI instalado localmente o una integración oficial equivalente. Encapsula autenticación, errores, límites de API y parseo de respuestas.
3. **Configuración y secretos**: valida parámetros y obtiene credenciales desde la configuración OCI local y el almacén seguro del sistema cuando sea compatible. Nunca imprime secretos ni vuelca respuestas crudas a los registros.
4. **Adaptadores de sistema operativo**: servicio systemd en Linux y servicio de Windows en Windows. Ambos ejecutan el mismo motor y usan directorios locales apropiados para configuración, estado y registros.

Se recomienda que la versión multiplataforma tenga un motor en Python con interfaces explícitas entre componentes. La implementación Bash actual se conserva como prototipo Linux y referencia del comportamiento; no debe convertirse en una dependencia del servicio de Windows ni asumirse equivalente sin migración y revisión.

## Flujo del motor

1. Cargar configuración local y rechazar valores ausentes, marcadores de posición o formatos inválidos.
2. Adquirir un bloqueo local para evitar dos procesos simultáneos.
3. Consultar si ya existe una instancia que satisfaga el criterio configurado. Si la respuesta es inválida o la consulta falla, no lanzar.
4. Consultar capacidad para cada dominio de disponibilidad configurado.
5. Intentar crear una instancia únicamente cuando la respuesta de OCI confirme explícitamente AVAILABLE.
6. Registrar el resultado con campos mínimos y redactados.
7. Si la capacidad no está disponible, reintentar con pausas y aleatoriedad acotadas. Si hay errores de autenticación, autorización, cuotas o configuración, detener o aplicar una espera larga y explicable; nunca mantener llamadas agresivas.
8. Tras una solicitud de creación aceptada o la detección de la instancia objetivo, entrar en estado terminal y no volver a lanzar automáticamente.
9. Si el resultado de una solicitud de creación es ambiguo por timeout o desconexión, volver a consultar el estado de instancias antes de intentar otra creación. No asumir que timeout significa que la operación falló.

## Máquina de estados conceptual

- STOPPED: servicio detenido por el usuario.
- VALIDATING_CONFIG: validación local.
- CHECKING_INSTANCE: búsqueda de instancia existente.
- CHECKING_CAPACITY: consulta de capacidad en OCI.
- WAITING_RETRY: espera antes de la siguiente comprobación.
- DRY_RUN_READY: capacidad confirmada, pero no se crearán recursos.
- LAUNCHING: petición de creación autorizada por la configuración.
- INSTANCE_FOUND: instancia objetivo detectada; no crear otra.
- LAUNCH_ACCEPTED: OCI aceptó la solicitud; verificar estado sin duplicar.
- NEEDS_ATTENTION: configuración, permisos o respuesta incierta requieren intervención.

## Privacidad y seguridad

- Todas las solicitudes de API salen directamente del equipo del usuario hacia OCI.
- No existe servidor de telemetría ni servicio de coordinación del proyecto.
- No se transmiten registros, métricas de uso, correo electrónico ni configuración a los mantenedores.
- Las claves privadas no se copian a la configuración de la aplicación. Se referencia la configuración OCI existente o un almacén seguro local.
- Nunca registrar contenido de claves, tokens, cabeceras de autenticación, OCID completos ni respuesta cruda de OCI.
- Redactar mensajes de error y conservar solo el código de error, la categoría y un identificador de correlación si no contiene datos sensibles.
- La configuración debe residir fuera del checkout Git, con permisos mínimos y acceso restringido a la cuenta del servicio.
- Los logs y el estado se almacenan localmente; el usuario puede eliminarlos con el servicio detenido.
- Sin conexiones entrantes, puertos de escucha, túneles, administración remota ni backend propio.

## Configuración segura por defecto

- DRY_RUN=true durante la configuración inicial.
- Creación real deshabilitada hasta que el usuario confirme una pantalla de resumen con región, forma, recursos, nombre y posibles cargos.
- Ninguna clave privada se solicita mediante entrada de texto de la terminal.
- Los campos secretos se obtienen desde el almacén del sistema o se introducen en la herramienta oficial de OCI.
- Los parámetros que puedan producir cargos se muestran antes de habilitar creación.
- Límites de reintentos, tiempos de espera y parada manual explícitos.
- No asumir que una capacidad informada como disponible garantiza que el lanzamiento tendrá éxito.

## Distribución

### Linux
- Paquete instalable con motor y comando de administración.
- Usuario de servicio dedicado, sin shell interactiva.
- Configuración en directorio del sistema protegido; estado y logs en directorios separados.
- Unidad systemd con permisos mínimos, sin reinicio infinito agresivo.
- Comandos explícitos para instalar, configurar, ver estado, ver logs redactados, detener, desinstalar y eliminar estado.

### Windows
- Instalador firmado cuando la distribución madura lo permita.
- Servicio de Windows con cuenta de servicio de privilegios mínimos.
- Configuración bajo ProgramData con ACL restrictivas; secretos gestionados por DPAPI o el almacén de credenciales apropiado, sujeto a validación de diseño.
- Comandos de administración para instalar, configurar, consultar estado, detener y desinstalar.
- No ejecutar el servicio como administrador permanente si no es necesario.

## Actualización y desinstalación

- La actualización no debe sobrescribir la configuración ni eliminar el estado del usuario.
- La desinstalación detiene y elimina el servicio, pero pregunta por separado si se desea borrar configuración, logs y estado.
- No borrar ni terminar instancias en OCI durante la desinstalación.
- No efectuar llamadas destructivas a OCI como parte de la instalación o desinstalación.

## Fases de desarrollo

1. Revisión estática y especificación del contrato del motor.
2. Diseño de la terminal interactiva y del modelo de configuración.
3. Implementación del motor independiente de plataforma.
4. Adaptadores de servicio Linux y Windows.
5. Pruebas simuladas y estáticas cuando sea posible ejecutarlas en un entorno autorizado.
6. Validación de CI cuando vuelva a haber cuota y runner.
7. Validación controlada con OCI, con consentimiento explícito y sin reutilizar credenciales de terceros.
8. Publicación de instaladores solo después de documentar qué se ha validado y qué limitaciones permanecen.
