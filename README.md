# Oracle Free Tier Watcher

Oracle Free Tier Watcher es un proyecto de software cuyo objetivo es comprobar periódicamente la disponibilidad de capacidad en Oracle Cloud Infrastructure (OCI) y, cuando la configuración del usuario lo autorice, intentar crear una instancia que cumpla los parámetros definidos.

La meta del proyecto es ofrecer una herramienta instalable en **Windows y Linux**, ejecutada como servicio en segundo plano. Mientras el equipo esté encendido y tenga conexión a Internet, el servicio podrá realizar comprobaciones automáticas con OCI, respetando los intervalos de espera, los límites de reintento y las condiciones de parada configuradas. La disponibilidad de capacidad no está garantizada: Oracle puede no disponer de recursos, y las cuotas, la región, la elegibilidad Free Tier y las políticas de la cuenta condicionan el resultado.

## Estado del proyecto

**En desarrollo. No hay todavía un instalador multiplataforma listo para uso general.**

El repositorio contiene una implementación inicial en Bash orientada a Linux y archivos de ejemplo para configuración, operación y endurecimiento. Todavía hacen falta el componente equivalente para Windows, la integración como servicio en ambos sistemas, pruebas automatizadas y de integración, y un procedimiento de instalación y actualización validado.

Por eso, por ahora, no se debe interpretar este repositorio como un instalador de un clic ni ejecutar la plantilla contra una cuenta de OCI sin revisar y probar cada parámetro.

## Cómo funcionará

1. El usuario instala y configura el watcher en su propio equipo.
2. El usuario proporciona localmente su configuración de OCI y los parámetros de la instancia que desea intentar crear.
3. El servicio espera a que el equipo esté encendido y tenga conexión a Internet.
4. El watcher comprueba primero si ya existe una instancia que coincida con el criterio configurado.
5. Consulta el informe de capacidad de OCI para los dominios de disponibilidad configurados y solo intenta crear la instancia cuando OCI devuelve explícitamente el estado `AVAILABLE` para la forma de cómputo solicitada.
6. Si no hay capacidad confirmada, espera y vuelve a comprobar con intervalos controlados. Si detecta la instancia objetivo o la solicitud de creación es aceptada, detiene los intentos para evitar duplicados. Los errores de configuración, autenticación, permisos, cuotas o API se gestionan con pausas y sin ciclos agresivos.

El comportamiento final —incluidos el intervalo de comprobación, la estrategia de reintentos, la selección de región y los criterios para reconocer una instancia— se documentará y probará antes de publicar instaladores estables.

## Privacidad y seguridad

Este proyecto está diseñado para mantener la configuración de cada usuario en su propio equipo. **No se deben incluir credenciales ni datos de cuentas en el repositorio.**

- Las claves privadas, tokens, archivos de configuración OCI, OCID, registros y datos de infraestructura deben permanecer localmente y fuera del control de versiones.
- No se deben enviar credenciales a un servicio central del proyecto. Cualquier futura función de telemetría deberá ser explícita, documentada y desactivada por defecto.
- Los ejemplos publicados deben usar únicamente valores ficticios y marcadores de posición.
- Los registros deben evitar secretos, respuestas completas de la API y detalles de infraestructura que no sean necesarios para diagnosticar el problema.
- La herramienta debe usar permisos mínimos, configuración protegida, reintentos acotados y mecanismos para impedir ejecuciones concurrentes.
- El usuario debe revisar las condiciones de Oracle Cloud, la elegibilidad Free Tier, las cuotas y los posibles cargos antes de habilitar la creación automática de recursos.

No publiques credenciales, claves, tokens, OCID reales, direcciones IP, registros operativos ni archivos de configuración. Si se expone una credencial, revócala o rótala; borrar el archivo en un commit posterior no elimina necesariamente el dato del historial de Git.

## Requisitos actuales de la implementación preliminar

La implementación Bash disponible está orientada a Linux y requiere Bash, OCI CLI, jq, flock y timeout. También necesita una configuración OCI local con los permisos mínimos necesarios y los parámetros válidos de la instancia.

Estos requisitos **no representan aún los requisitos de una futura versión para Windows**. La compatibilidad con Windows, la instalación como servicio y la puesta en marcha guiada se publicarán cuando estén implementadas y verificadas.

## Instalación

**El instalador todavía no está disponible.** No hay un procedimiento de instalación multiplataforma estable que podamos recomendar por ahora.

Mientras el proyecto esté en desarrollo, consulta los ejemplos y documentos antes de ejecutar la implementación preliminar:

- [Configuración y seguridad](docs/CONFIGURATION.md)
- [Operación y ciclo de vida](docs/OPERATIONS.md)
- [Ejemplo de configuración](config/watcher.env.example)
- [Ejemplo de servicio systemd para Linux](systemd/oracle-free-tier-watcher.service.example)

No habilites la creación automática hasta completar las pruebas en modo de simulación, verificar permisos y parámetros y confirmar los posibles costos. Los archivos de ejemplo no son un instalador ni una configuración lista para producción.

## Archivos principales

- src/oracle-free-tier-watcher.sh: implementación preliminar para Linux.
- config/watcher.env.example: ejemplo de configuración con marcadores de posición.
- systemd/oracle-free-tier-watcher.service.example: ejemplo de servicio para Linux.
- docs/CONFIGURATION.md: configuración local y medidas de seguridad.
- docs/ARCHITECTURE.md: arquitectura local multiplataforma propuesta.
- docs/STATIC-REVIEW.md: hallazgos estáticos y validaciones pendientes.
- docs/INTERACTIVE-CLI.md: diseño de la terminal interactiva y el almacenamiento seguro.
- docs/OPERATIONS.md: ejecución, verificación y parada.
- tests/test-mocked-oci.sh: prueba local con respuestas OCI simuladas; no crea recursos.
- .gitignore: exclusiones para archivos locales sensibles.

## Licencia

Pendiente de definir.
