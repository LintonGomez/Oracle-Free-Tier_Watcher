# Operación

## Antes de ejecutar

1. Verifica el equipo de destino, la ruta de OCI CLI, el perfil y archivo de configuración local, la región, el compartment, la imagen, la subnet, la clave pública SSH y la forma de cómputo.
2. Comprueba que el criterio de nombre o identificación no coincida con una instancia distinta que quieras conservar.
3. Confirma cuotas, elegibilidad Free Tier y posibles cargos.
4. Empieza con el modo de simulación y revisa los registros localmente. La implementación consulta primero el informe de capacidad de OCI para cada dominio configurado y solo intenta lanzar cuando recibe el estado explícito AVAILABLE.

## Ciclo de vida del servicio

La unidad de systemd es un ejemplo y no se habilita automáticamente. Antes de instalarla, adapta el usuario, las rutas, el archivo de entorno y los permisos; después revisa manualmente su configuración.

Consulta el estado:

```bash
systemctl status oracle-free-tier-watcher.service --no-pager
systemctl is-enabled oracle-free-tier-watcher.service
systemctl is-active oracle-free-tier-watcher.service
```

Para detener el servicio y evitar que arranque automáticamente:

```bash
sudo systemctl disable --now oracle-free-tier-watcher.service
```

Verifica el resultado; se espera disabled e inactive. Comprueba por separado si se instaló un temporizador de systemd u otro programador. La unidad de ejemplo no se reinicia automáticamente; cualquier temporizador debe revisarse antes de habilitarlo.

## Registros y estado

Guarda los registros y el estado de ejecución fuera del directorio del código, con permisos restrictivos. No compartas registros sin revisar: las respuestas de OCI CLI pueden contener identificadores u otros detalles de infraestructura.

## Tratamiento de errores

Los errores transitorios de capacidad pueden reintentarse con esperas limitadas. Los errores de autenticación, autorización, cuotas, configuración o recursos inexistentes no deben generar llamadas repetidas de forma agresiva. Revisa los registros de manera privada y corrige la causa antes de habilitar nuevos intentos. No publiques respuestas crudas de OCI ni salida sin redactar. Si el JSON devuelto al consultar instancias no es válido, la implementación debe detener el flujo de lanzamiento y aplicar una espera segura.

## Pruebas locales con OCI simulado

Desde la raíz del repositorio, ejecuta:

```bash
bash -n src/oracle-free-tier-watcher.sh
bash tests/test-mocked-oci.sh
```

La prueba utiliza un ejecutable OCI falso y respuestas JSON de ejemplo. No llama a la red, no lee la configuración real de OCI y no crea recursos. Comprueba tres casos: capacidad disponible en modo `DRY_RUN`, capacidad no disponible y una instancia existente. Requiere Bash, `jq`, `flock`, `timeout` y utilidades básicas del sistema. Es una prueba de humo local, no sustituye ShellCheck ni una integración controlada con OCI.
