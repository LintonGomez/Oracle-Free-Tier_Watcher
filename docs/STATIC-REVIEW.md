# Revisión estática inicial

## Alcance

Revisión de lectura del código y de los archivos de configuración. No se ejecutaron el watcher, pruebas unitarias, pruebas simuladas, ShellCheck, GitHub Actions ni llamadas a OCI. Los hallazgos que siguen son análisis estático y requieren validación posterior.

## Hallazgos y decisiones

### Servicio systemd de larga duración

La plantilla del servicio declaraba Type=oneshot aunque el script principal contiene un bucle de vigilancia que no termina por sí solo. Ese tipo de unidad no expresa correctamente la intención de un proceso de larga duración. Se cambió la plantilla a Type=simple. Esta corrección es estática y todavía no se ha validado en una máquina Linux.

### Respuesta de capacidad OCI

El script debe tratar cualquier JSON malformado o estado desconocido como capacidad no confirmada. Se ajustó el parseo para usar UNKNOWN si no se puede extraer un estado de texto válido. La compatibilidad exacta del esquema de respuesta con la versión instalada de OCI CLI aún debe verificarse en una etapa de validación controlada.

### Reintentos por limitación de API

Se ajustó el flujo para evitar que una respuesta de throttling provoque dos esperas consecutivas. El comportamiento temporal real aún no se ha medido.

### Resultado ambiguo al crear una instancia

Un timeout o una desconexión durante una solicitud de creación no demuestra que OCI no haya aceptado la operación. La implementación multiplataforma debe volver a consultar instancias antes de considerar otro intento, para reducir el riesgo de duplicados. Este requisito está registrado en la arquitectura propuesta; no se considera resuelto por la implementación Bash actual.

### Estado del servicio y ejecución de instalación

No se debe presentar la plantilla systemd actual como instalador listo para producción. La cuenta de servicio, la configuración, los permisos, la ruta de OCI CLI y el acceso a la clave deben revisarse como un conjunto al implementar el instalador.

## Pendiente de validación

- Sintaxis Bash y análisis ShellCheck.
- Pruebas simuladas para capacidad disponible, capacidad no disponible, instancia existente, errores de API, throttling y JSON malformado.
- Verificar que los logs y el estado no contienen credenciales ni OCID completos.
- Validar comportamiento de parada, bloqueo, timeouts y solicitudes de creación con resultado ambiguo.
- Revisar el historial completo del repositorio para secretos que hayan podido quedar en commits antiguos.
- Validar el servicio Linux y diseñar/validar el servicio Windows.
- Confirmar el esquema de la API de informe de capacidad con la documentación vigente de OCI CLI.
- Ejecutar CI cuando se disponga nuevamente de cuota y runner.

No interpretar esta revisión como prueba de que el programa funciona correctamente o de que el historial completo está libre de secretos.
