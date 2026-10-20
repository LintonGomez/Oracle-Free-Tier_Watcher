# Configuración y seguridad

## Nunca guardes secretos en Git

Este repositorio es público. Mantén fuera del repositorio:
- Claves privadas de la API de OCI, claves SSH privadas, tokens y credenciales de sesión.
- OCID reales de tenancy, compartment, imagen, subnet e instancias.
- Registros operativos, salida de CLI y archivos de estado.
- Cualquier configuración local que contenga identificadores de infraestructura.

Usa el mecanismo de configuración y archivos de clave local de OCI CLI o un gestor de secretos adecuado. Nunca pegues claves privadas en incidencias, pull requests, registros de GitHub Actions ni en este repositorio. Los archivos de ejemplo deben contener solo marcadores de posición. La configuración OCI y la clave privada deben tener permisos restrictivos y estar accesibles únicamente para la cuenta de servicio que las necesita.

## Preparación local

Crea un directorio de configuración protegido en el equipo de destino y copia config/watcher.env.example a esa ubicación. Sustituye los valores de ejemplo y asigna propietario y permisos adecuados. No guardes la configuración dentro del checkout del repositorio ni la sincronices públicamente.

Comprueba que el perfil OCI pueda consultar el compartment previsto y que la imagen, subnet, forma de cómputo y dominio de disponibilidad sean válidos en la región seleccionada. Confirma la compatibilidad de la imagen y la forma de cómputo, además de las cuotas disponibles.

La cuenta de servicio debe tener únicamente los permisos IAM de OCI necesarios para las acciones previstas. No concedas administración de toda la tenancy si no es imprescindible. La unidad de systemd de ejemplo utiliza un usuario dedicado y restringe el acceso a directorios del sistema; adapta las rutas y permisos de forma coherente con ese aislamiento.

## Simulación antes de crear recursos

Mantén DRY_RUN=true al comenzar. Verifica la carga de configuración, la detección de instancias, los registros y la parada. Cambia DRY_RUN a false únicamente después de revisar los parámetros de lanzamiento y confirmar que son correctos. Crear una instancia modifica recursos en la nube y puede generar cargos fuera de las cuotas elegibles para Free Tier.

## Higiene del repositorio público

Antes de cada commit, revisa los cambios y ejecuta un escáner de secretos. No publiques registros ni archivos de estado. Si se expone una credencial real, revócala o rótala. Eliminar un archivo en un commit posterior no elimina las versiones anteriores del historial de Git.

## Principio de privacidad

La configuración, las credenciales y los identificadores de cada instalación deben permanecer en el equipo del usuario. El proyecto no necesita publicar ni compartir esos datos para que el watcher funcione. Cualquier telemetría futura debe documentarse claramente, requerir una decisión explícita del usuario y estar desactivada por defecto.
