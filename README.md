# Oracle Free Tier Watcher

Herramienta para vigilar la disponibilidad de capacidad de Oracle Cloud Infrastructure (OCI) y, cuando está explícitamente configurada, intentar crear una instancia Free Tier. La implementación se basa en el mecanismo recuperado de un servidor de operación, pero este repositorio solo contiene una plantilla saneada y parametrizada.

> **Seguridad:** este repositorio es público. No publiques credenciales OCI, claves privadas, tokens, OCID de tenancy/compartment/subnet/imagen/instancia, direcciones IP privadas ni logs de producción. Los identificadores operativos deben permanecer en configuración local no versionada. Si un secreto se publica accidentalmente, elimínalo del repositorio y rota/revoca la credencial; borrar el archivo de un commit no lo elimina del historial.

## Estado

- Repositorio inicializado con estructura pública saneada.
- La plantilla no está lista para desplegarse sin configurar y validar los recursos específicos de tu tenancy.
- La instancia de producción existente no se modifica por este repositorio.
- El servicio de systemd en producción debe administrarse por separado; que el script termine al detectar una instancia existente no sustituye deshabilitar su arranque automático.

## Mecanismo recuperado

La implementación original empleaba:
- OCI CLI en una máquina Linux.
- Una consulta previa para encontrar una instancia existente con el nombre configurado.
- Shape `VM.Standard.A1.Flex`, región y parámetros de computación configurados explícitamente.
- Reintentos con pausa y jitter, rotación de dominios de disponibilidad.
- Backoff ante throttling y pausas más largas ante errores que requieren intervención.
- Registro de estado y un lock para evitar ejecuciones concurrentes.
- Salida cuando encuentra una instancia existente o consigue crearla.

La versión saneada mantiene estas ideas en una configuración explícita, y evita incrustar OCID en el código. Antes de producción requiere pruebas en un entorno controlado.

## Requisitos

- Linux con Bash, `oci`, `jq`, `flock` y `timeout`.
- OCI CLI autenticada con una configuración local de acceso limitado.
- Permisos OCI mínimos necesarios para listar instancias y lanzar una instancia en el compartment elegido.
- Configuración local con los identificadores correctos de tenancy/compartment, imagen, subnet y clave pública SSH.

## Uso

1. Revisa `docs/CONFIGURATION.md`.
2. Copia `config/watcher.env.example` a una ruta local como `/etc/oracle-free-tier-watcher/watcher.env` (no a Git).
3. Sustituye todos los valores de ejemplo por los valores correctos de tu entorno.
4. Protege el archivo con propietario administrativo y permisos `0600`.
5. Ejecuta primero en modo de validación sin lanzamiento de recursos y revisa los logs.
6. Instala el servicio solo después de completar las pruebas. La plantilla de systemd está en `systemd/oracle-free-tier-watcher.service.example`.

No actives reintentos automáticos hasta verificar región, cuotas, costos, permisos y comportamiento de parada. El script debe detenerse cuando ya exista una instancia objetivo.

## Archivos

- `src/oracle-free-tier-watcher.sh`: script saneado y parametrizado.
- `config/watcher.env.example`: nombres de variables y valores de ejemplo no utilizables en producción.
- `systemd/oracle-free-tier-watcher.service.example`: ejemplo de unidad systemd.
- `docs/CONFIGURATION.md`: configuración, seguridad y operación.
- `docs/OPERATIONS.md`: ejecución, verificación y parada.
- `.gitignore`: excluye configuración local, logs, estados y credenciales.

## Licencia

Pendiente de definir por el propietario del repositorio.