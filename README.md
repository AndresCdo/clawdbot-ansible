# Clawdbot Ansible Deployment

Este repositorio contiene playbooks de Ansible para desplegar Clawdbot en una máquina remota Ubuntu, replicando la configuración actual existente en la máquina local.

Incluye la instalación de Node.js via NVM, instalación de Clawdbot global, configuración del servicio systemd user, script de monitoreo y cron job para supervisión automática.

## Estructura

```
clawdbot-ansible/
├── inventories/           # Inventarios de hosts
│   └── local.yml         # Ejemplo para localhost
├── group_vars/           # Variables globales
│   └── all.yml           # Configuración principal
├── playbooks/            # Playbooks de Ansible
│   └── clawdbot.yml      # Playbook principal
├── roles/                # Roles de Ansible
│   ├── nvm_node/         # Instala NVM y Node.js
│   ├── clawdbot_install/ # Instala Clawdbot globalmente
│   ├── clawdbot_config/  # Configura archivos de clawdbot
│   ├── systemd_service/  # Configura servicio systemd user
│   └── cron_monitor/     # Configura cron job y script de monitoreo
├── files/                # Archivos estáticos
│   ├── clawd/            # Workspace de clawdbot (scripts)
│   ├── config/           # Configuración de clawdbot.json
│   └── systemd/          # Servicio systemd original
├── templates/            # Plantillas Jinja2 (no utilizadas directamente)
└── README.md
```

## Requisitos

- Ansible 2.9+
- Host remoto Ubuntu (o similar) con acceso SSH y privilegios sudo.
- El usuario objetivo debe existir (por defecto `ubuntu`). Cambiar variable `clawdbot_user` según necesidad.

## Uso

1. Clonar el repositorio en la máquina de control.
2. Editar `group_vars/all.yml` para ajustar variables:
   - `clawdbot_user`: usuario bajo el cual se instalará clawdbot.
   - `clawdbot_user_id`: UID del usuario (por defecto 1000).
   - `clawdbot_gateway_token` y `clawdbot_gateway_auth_token`: tokens de autenticación (cambiar por valores seguros).
   - `clawdbot_whatsapp_allow_from`: lista de números permitidos para WhatsApp.
   - Otras variables según necesidad.
3. Crear un inventario en `inventories/` con los hosts destino. Ejemplo `production.yml`.
4. Ejecutar el playbook:

```bash
ansible-playbook -i inventories/production.yml playbooks/clawdbot.yml
```

Para probar en localhost (con conexión local):

```bash
ansible-playbook -i inventories/local.yml playbooks/clawdbot.yml --ask-become-pass
```

## Variables importantes

Consultar `group_vars/all.yml` para la lista completa. Algunas destacadas:

- `node_version`: versión de Node.js (por defecto 22.20.0).
- `clawdbot_version`: versión de Clawdbot (por defecto 2026.1.24-3).
- `clawdbot_gateway_port`: puerto del gateway (18789).
- `cron_schedule`: frecuencia del cron job (`*/3 * * * *` cada 3 minutos).

## Seguridad

- Los tokens de autenticación deben ser almacenados de forma segura. Se recomienda usar Ansible Vault para cifrar `group_vars/all.yml` o usar variables de entorno.
- No cometer archivos con tokens reales. El repositorio incluye placeholders.

## Detalles de implementación

### NVM y Node.js
Se instala NVM en el directorio del usuario y se instala la versión especificada de Node.js. Se agrega la configuración al `.bashrc`.

### Clawdbot
Se instala globalmente via npm desde el registro público.

### Configuración
Se genera `~/.clawdbot/clawdbot.json` a partir de la plantilla, incluyendo configuración de WhatsApp, gateway, agentes, etc.

### Servicio systemd
Se crea un servicio user systemd (`~/.config/systemd/user/clawdbot-gateway.service`) que se ejecuta bajo el usuario, con reinicio automático.

### Monitoreo
Se despliega un script de monitoreo (`~/clawd/monitor_clawdbot.sh`) que verifica el estado del gateway y WhatsApp, realiza recuperación automática y aplica backoff exponencial. Un cron job lo ejecuta cada 3 minutos.

## Personalización

- Para agregar scripts adicionales al workspace, colocarlos en `files/clawd/` y modificar el rol `clawdbot_config`.
- Para modificar el comportamiento del monitor, editar la plantilla `roles/cron_monitor/templates/monitor_clawdbot.sh.j2`.
- Para cambiar puertos o tokens, actualizar las variables en `group_vars/all.yml`.

## Solución de problemas

- Verificar que el usuario tenga sesión systemd activa (logueado al menos una vez). El playbook habilida `linger` para permitir servicios sin sesión activa.
- Si el gateway no arranca, revisar logs con `journalctl --user -u clawdbot-gateway.service`.
- El script de monitoreo escribe logs en `~/clawd/monitor_log.txt`.

## Licencia

MIT