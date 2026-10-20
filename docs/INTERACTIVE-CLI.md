# Diseño de la terminal interactiva

## Estado

Especificación de experiencia de usuario. No es una terminal implementada y no implica que la configuración o el almacenamiento seguro ya funcionen.

## Principios

- La terminal es local y no se conecta a un servidor del proyecto.
- La comunicación de red necesaria se limita a las API de OCI.
- Nunca pedir ni mostrar una clave privada pegando su contenido en el asistente de configuración.
- No imprimir secretos, credenciales, OCID completos ni respuestas crudas de API.
- Permitir cancelar en cualquier paso sin guardar una configuración parcial como válida.
- Explicar cada permiso solicitado y distinguir consultas de acciones que crean recursos.
- El modo seguro es el predeterminado y la creación real requiere confirmación explícita.

## Menú principal propuesto

~~~text
Oracle Free Tier Watcher
Estado: no configurado

1. Configurar OCI
2. Revisar configuración
3. Ejecutar diagnóstico de solo lectura
4. Consultar estado del watcher
5. Ver últimos registros (redactados)
6. Iniciar servicio
7. Detener servicio
8. Cambiar política de comprobación
9. Desinstalar
0. Salir
~~~

Las opciones que todavía no estén implementadas deben mostrarse como no disponibles, no como si hubieran funcionado.

## Asistente de configuración

1. **Aviso de privacidad**: indicar que el programa no tiene backend, que las solicitudes van directamente a OCI y que la cuenta del usuario determina permisos y posibles cargos.
2. **Método de autenticación**: preferir una configuración OCI CLI ya creada o dirigir al usuario al procedimiento oficial para crearla. Nunca pedir contraseñas del portal ni importar una clave privada pegada en la terminal.
3. **Perfil y región**: validar la existencia local del perfil y mostrar solo nombres necesarios; no mostrar rutas de claves ni material de autenticación.
4. **Parámetros de instancia**: pedir compartment, región, dominio(s) de disponibilidad, forma, OCPU, memoria, imagen, subnet, volumen de arranque y nombre objetivo, según lo requerido por OCI.
5. **Validación local**: comprobar sintaxis, campos obligatorios y referencias locales sin crear recursos.
6. **Resumen**: mostrar valores de infraestructura que el usuario necesita revisar, ocultando secretos. Advertir que Free Tier, cuotas y elegibilidad dependen de OCI y que puede haber cargos.
7. **Guardar**: escribir la configuración en el directorio de sistema protegido, con permisos/ACL mínimos. Guardar de forma atómica: escribir archivo temporal protegido y renombrarlo solo después de validar.
8. **Modo de ejecución**: mantener simulación activada inicialmente. La habilitación de creación real debe ser una acción separada, con confirmación clara.

## Almacenamiento de credenciales

- No implementar una bóveda criptográfica propia.
- No copiar la clave privada OCI ni la clave SSH privada al directorio de la aplicación.
- En Linux, utilizar permisos del sistema y la configuración OCI local, con acceso limitado a la cuenta del servicio.
- En Windows, evaluar DPAPI o Windows Credential Manager para cualquier secreto que realmente deba custodiar el programa. El diseño final debe considerar que un servicio puede ejecutarse bajo una cuenta distinta a la del usuario interactivo.
- Una clave pública SSH no es un secreto, pero su ruta y contenido no deben incluirse en logs si no son necesarios.
- Los archivos de configuración pueden incluir OCID y metadatos sensibles aunque no incluyan contraseñas; tratarlos como datos privados.
- No enviar credenciales o configuración a mantenedores, analítica, crash reporting o telemetría.

## Mensajes de error

Mostrar mensajes accionables y redactados. Ejemplos:

- No se pudo leer el perfil OCI seleccionado. Revisa la configuración local y los permisos.
- OCI rechazó la solicitud por permisos insuficientes. No se harán nuevos intentos rápidos.
- OCI no confirmó capacidad disponible. Se volverá a consultar tras la pausa configurada.
- La respuesta fue incierta. Se verificará si existe una instancia antes de considerar otro lanzamiento.

No mostrar el comando completo si incluye rutas privadas, credenciales, OCID o datos que el usuario no necesita para resolver el problema.

## Comandos no interactivos

Además de la terminal guiada, planificar comandos aptos para administración local:

- watcher configure
- watcher validate
- watcher status
- watcher logs --tail (con redacción)
- watcher service install
- watcher service start|stop
- watcher service uninstall

Los nombres son provisionales. La implementación debe definir un contrato consistente para Windows y Linux; no prometer compatibilidad antes de validarla.

## Confirmación de creación real

Antes de desactivar el modo de simulación, mostrar una pantalla con:
- Región y dominio(s) de disponibilidad.
- Forma, OCPU, memoria y volumen.
- Imagen, subnet y nombre objetivo.
- Política de reintentos y tiempo de espera.
- Riesgo de que no haya capacidad y advertencia de posibles cargos.

Solicitar una confirmación inequívoca. La opción de salida o cancelación nunca debe activar la creación real.
