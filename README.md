# Clawdbot Ansible Deployment

Este repositorio contiene playbooks de Ansible para desplegar Clawdbot en una máquina remota Ubuntu, replicando la configuración actual existente en la máquina local.

Incluye la instalación de Node.js via NVM, instalación de Clawdbot global, configuración del servicio systemd user, script de monitoreo inteligente, health checks, deploy quirúrgico y cron job para supervisión automática.

## ✨ Características Principales

- 🚀 **Graceful Reload**: Reinicio sin downtime usando `systemctl reload`
- 🔍 **Health Check Avanzado**: Verificación multi-capas de salud del sistema
- 📊 **Detección de Cambios**: Auto-detección de actualizaciones de código
- 🔄 **Deploy Quirúrgico**: Backup automático + rollback + health checks
- 📈 **Métricas**: Logging de recursos (CPU, memoria) cada 15 minutos
- 🛡️ **Recuperación Automática**: Backoff exponencial y deep cleanup

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
│   ├── systemd_service/  # Configura servicio systemd user (mejorado)
│   └── cron_monitor/     # Monitor, health check y deploy scripts
├── files/                # Archivos estáticos
│   ├── clawd/            # Workspace de clawdbot
│   ├── config/           # Configuración de clawdbot.json
│   └── systemd/          # Servicio systemd
├── MEJORAS.md            # Documentación de mejoras implementadas
└── README.md             # Este archivo
```

## 🚀 Uso Rápido

### 1. Instalación Inicial

```bash
# Configurar variables
vim group_vars/all.yml

# Ejecutar playbook
ansible-playbook -i inventories/local.yml playbooks/clawdbot.yml --ask-become-pass
```

### 2. Deploy de Nueva Versión

```bash
# En el servidor, usar el script de deploy:
~/clawd/deploy.sh latest                    # Deploy última versión
~/clawd/deploy.sh 2026.1.24-4               # Deploy versión específica
~/clawd/deploy.sh --mode=reload             # Solo graceful reload
```

### 3. Monitoreo y Health Checks

```bash
# Health check completo
~/clawd/health_check.sh --verbose

# Ver logs
tail -f ~/clawd/monitor_log.txt
tail -f ~/clawd/service.log

# Status del servicio
systemctl --user status clawdbot-gateway
```

## ⚙️ Configuración

### Variables Importantes (`group_vars/all.yml`)

```yaml
# Versión de Clawdbot
clawdbot_version: "2026.1.24-3"

# Configuración de monitor
enable_code_change_detection: true
enable_resource_metrics: true
metrics_log_interval: 5
enable_graceful_reload: true

# Health check
health_check_max_memory_percent: 80
health_check_max_cpu_percent: 90

# Deploy
deploy_backup_retention: 10
deploy_rollback_on_failure: true
```

### Tokens y Seguridad

⚠️ **IMPORTANTE**: Editar estos valores antes de desplegar:

```yaml
clawdbot_gateway_token: "CHANGE_ME_GATEWAY_TOKEN"
clawdbot_gateway_auth_token: "CHANGE_ME_AUTH_TOKEN"
clawdbot_whatsapp_allow_from:
  - "+1234567890"  # Tu número de WhatsApp
```

Recomendado usar Ansible Vault:
```bash
ansible-vault encrypt group_vars/all.yml
ansible-playbook -i inventories/production.yml playbooks/clawdbot.yml --ask-vault-pass
```

## 📁 Archivos del Workspace

Después del despliegue, en `~/clawd/`:

```
~/clawd/
├── monitor_clawdbot.sh      # Monitor inteligente (cron)
├── health_check.sh          # Health check avanzado
├── deploy.sh                # Script de deploy quirúrgico
├── monitor_log.txt          # Log del monitor
├── service.log              # Log del servicio systemd
└── backups/                 # Backups automáticos
    └── 20260130_120000/
        ├── version.txt
        ├── clawdbot.json
        └── service_status.log
```

## 🔧 Comandos Útiles

### Servicio Systemd

```bash
# Graceful reload (rápido, recomendado)
systemctl --user reload clawdbot-gateway.service

# Full restart (con cleanup de procesos)
systemctl --user restart clawdbot-gateway.service

# Ver status
systemctl --user status clawdbot-gateway.service

# Ver logs del servicio
journalctl --user -u clawdbot-gateway.service -f
```

### Health Checks

```bash
# Check completo
~/clawd/health_check.sh

# Verbose
~/clawd/health_check.sh --verbose

# Timeout custom
~/clawd/health_check.sh --timeout=30
```

### Deploys

```bash
# Deploy de última versión
~/clawd/deploy.sh latest

# Deploy específico
~/clawd/deploy.sh 2026.1.24-5

# Solo reload (rápido)
~/clawd/deploy.sh --mode=reload

# Hot deploy (para desarrollo)
~/clawd/deploy.sh --mode=hot
```

## 📊 Monitoreo

El script de monitoreo (`monitor_clawdbot.sh`) se ejecuta cada 3 minutos y:

- ✅ Verifica que el gateway responda
- ✅ Chequea estado de WhatsApp
- ✅ Detecta cambios de código (npm updates)
- ✅ Loguea métricas cada 15 minutos
- ✅ Realiza graceful reload o restart según necesidad
- ✅ Aplica backoff exponencial para evitar spam
- ✅ Limpia procesos de navegador huérfanos

### Logs

- **monitor_log.txt**: Estado del gateway, errores, intentos de restart
- **service.log**: Eventos del servicio systemd
- **deploy.log**: Historial de deploys y rollbacks

## 🛠️ Solución de Problemas

### Servicio no inicia

```bash
# Verificar errores
journalctl --user -u clawdbot-gateway.service --since "1 hour ago"

# Verificar health check
~/clawd/health_check.sh --verbose

# Verificar puerto
sudo netstat -tlnp | grep 18789
```

### WhatsApp no conecta

```bash
# Forzar reconexión
systemctl --user stop clawdbot-gateway
pkill -f "chrome.*clawdbot"
sleep 3
systemctl --user start clawdbot-gateway
sleep 10
clawdbot channels login
```

### Deploy falló

```bash
# Ver log del deploy
cat ~/clawd/deploy.log

# Ver último backup
ls -la ~/clawd/backups/
cat ~/clawd/backups/latest_backup.txt

# El rollback es automático, pero si necesitas forzar:
~/clawd/deploy.sh $(cat ~/clawd/backups/*/version.txt | tail -1) --mode=full
```

## 📝 Requisitos

- Ansible 2.9+
- Ubuntu 20.04+ (o similar)
- Acceso SSH con privilegios sudo
- Usuario objetivo existente (por defecto `ubuntu`)

## 📖 Más Información

Ver **[MEJORAS.md](MEJORAS.md)** para documentación detallada de:
- Arquitectura de mejoras
- Flujos de trabajo avanzados
- Configuración de variables
- Troubleshooting extendido
- Próximos pasos (Fase 2)

## 📄 Licencia

MIT