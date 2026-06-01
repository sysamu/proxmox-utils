# Proxmox Backup Server 3.x → 4.x — Procedimiento de Actualización Seguro

> **Caso de uso documentado:** PBS 3.4.6 instalado encima de **Debian 12 (Bookworm)** en una instancia **OVH Public Cloud B3-16**.
> **Versión destino:** PBS 4.2 sobre Debian 13 (Trixie), kernel 6.14.
> **Fuente oficial:** <https://pbs.proxmox.com/wiki/index.php/Upgrade_from_3_to_4>

---

## 1. Resumen ejecutivo

La actualización mayor de PBS 3 → 4 implica saltar de **Debian 12 (Bookworm) a Debian 13 (Trixie)** vía `apt dist-upgrade`. Es una operación reversible **solo mediante snapshot/backup completo de la VM**, no mediante rollback de paquetes. Por eso, en una instancia cloud sin acceso IPMI físico, los pasos previos de snapshot y validación son tan importantes como el upgrade mismo.

**Riesgo en una OVH B3-16:**
- ✅ Bajo riesgo de cambio de nombre de NIC (driver virtio estable entre kernels).
- ✅ Bajo riesgo de incompatibilidad de hardware (es una VM virtualizada).
- ⚠️ Sin IPMI físico — la única vía de recuperación es la **consola web de Horizon/OVH Cloud Panel** o restaurar el snapshot.
- ⚠️ La sesión SSH puede colgarse durante el `dist-upgrade`; debe ejecutarse dentro de `tmux` o `screen`.

**Tiempo estimado:** 30–90 min, dominado por la descarga de paquetes y el reinicio.

---

## 2. Pre-requisitos obligatorios

| # | Requisito | Verificación |
|---|-----------|--------------|
| 1 | Snapshot de la instancia OVH **completo y reciente** | Panel OVH → Public Cloud → Instances → Snapshot |
| 2 | Acceso comprobado a la **consola web OVH** (no solo SSH) | Panel OVH → Instance → "..." → Console |
| 3 | PBS en versión **3.4.2 o superior** | `proxmox-backup-manager versions` |
| 4 | Sin tareas de backup, garbage collection, verify, sync o prune **en curso ni programadas durante la ventana** | `proxmox-backup-manager task list --all` y revisar UI |
| 5 | **Mínimo 10 GB libres en `/`** | `df -h /` |
| 6 | Conexión vía `tmux` o `screen` | `tmux new -s pbs-upgrade` |
| 7 | Backup de `/etc/proxmox-backup` descargado fuera del servidor | Ver §3 |
| 8 | Ventana de mantenimiento comunicada a stakeholders | — |

> **Si falla cualquiera de estos puntos, NO continuar.**

---

## 3. Procedimiento manual paso a paso

> Para una versión automatizada de los pasos 3–9, ver §5 (`pbs-upgrade-3-to-4.sh`). Los pasos 1, 2, y 10 deben hacerse a mano siempre.

### Paso 1 — Snapshot OVH

En el panel OVH Public Cloud:

1. **Public Cloud → Instances → tu instancia → "..." → Create snapshot**.
2. Nombre sugerido: `pbs-pre-upgrade-v4-YYYYMMDD`.
3. Esperar a que el snapshot termine antes de continuar (estado "OK").

Si la actualización falla de forma catastrófica, OVH permite **crear una nueva instancia desde este snapshot** y reasociar la IP. **Coste:** se factura el almacenamiento del snapshot mientras exista.

### Paso 2 — Conectarse vía `tmux`

```bash
ssh root@<tu-instancia>
tmux new -s pbs-upgrade
```

Si la sesión SSH cae durante el upgrade, reconectarse y hacer `tmux attach -t pbs-upgrade`.

### Paso 3 — Pre-checks

```bash
# Versión actual de PBS
proxmox-backup-manager versions --verbose

# Espacio libre en raíz
df -h /

# Tareas activas (no debe haber backups, GC, verify ni sync corriendo)
proxmox-backup-manager task list --all | head -30

# Estado de los datastores
proxmox-backup-manager datastore list
```

### Paso 4 — Actualizar PBS 3 a la última 3.4.x

```bash
apt update
apt dist-upgrade -y
proxmox-backup-manager versions
```

La salida debe mostrar **`proxmox-backup-server 3.4.x`** donde `x >= 2`. Si está por debajo, **detenerse y resolver primero**.

### Paso 5 — Backup de configuración

```bash
mkdir -p /root/pbs-upgrade-backup
tar czf "/root/pbs-upgrade-backup/pbs3-etc-$(date -I).tar.gz" -C /etc proxmox-backup
cp /etc/apt/sources.list /root/pbs-upgrade-backup/sources.list.bookworm.bak
cp -r /etc/apt/sources.list.d /root/pbs-upgrade-backup/sources.list.d.bookworm.bak
ls -lh /root/pbs-upgrade-backup/
```

**Descargar el directorio `/root/pbs-upgrade-backup/` fuera del servidor** (a tu workstation o a un bucket S3):

```bash
# Desde tu workstation
scp -r root@<tu-instancia>:/root/pbs-upgrade-backup/ ./pbs-backup-local/
```

### Paso 6 — Modo mantenimiento en datastores (opcional pero recomendado)

```bash
# Listar datastores
proxmox-backup-manager datastore list

# Para cada datastore, activar read-only
proxmox-backup-manager datastore update <DATASTORE-ID> --maintenance-mode read-only
```

Esto previene que clientes inicien backups durante la ventana.

### Paso 7 — Ejecutar `pbs3to4 --full`

```bash
pbs3to4 --full
```

Esta herramienta de Proxmox identifica problemas potenciales **sin hacer cambios**. Revisa la salida con atención. **Todo lo que aparezca como FAIL debe resolverse antes de continuar.**

### Paso 8 — Cambiar repositorios a Trixie

```bash
# Reemplazar bookworm → trixie en el sources.list principal
sed -i.bak 's/bookworm/trixie/g' /etc/apt/sources.list

# Revisar manualmente todos los repos extra
ls /etc/apt/sources.list.d/
grep -r bookworm /etc/apt/sources.list.d/ || echo "OK: no quedan referencias bookworm"

# Eliminar el repositorio PBS 3 anterior (NO el de Debian)
rm -f /etc/apt/sources.list.d/pbs-enterprise.list \
      /etc/apt/sources.list.d/pbs-no-subscription.list \
      /etc/apt/sources.list.d/pbs-install-repo.list 2>/dev/null

# Añadir repositorio PBS 4 — elegir UNO de los dos:

# Opción A — Sin suscripción (recomendado para entornos no-prod)
cat > /etc/apt/sources.list.d/pbs-no-subscription.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pbs
Suites: trixie
Components: pbs-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

# Opción B — Empresa (si tienes suscripción)
# cat > /etc/apt/sources.list.d/pbs-enterprise.sources <<'EOF'
# Types: deb
# URIs: https://enterprise.proxmox.com/debian/pbs
# Suites: trixie
# Components: pbs-enterprise
# Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
# EOF

# Verificar que el keyring esté presente
test -f /usr/share/keyrings/proxmox-archive-keyring.gpg && echo "OK keyring" || \
  apt install -y proxmox-archive-keyring

apt update
```

> **Solo debe estar activo UN repositorio PBS** (no-subscription O enterprise, no ambos).

### Paso 9 — `dist-upgrade` mayor

```bash
apt update
apt dist-upgrade
```

**Durante el proceso aparecerán prompts interactivos:**

| Prompt | Respuesta recomendada |
|--------|----------------------|
| `apt-listchanges` | Salir con `q` |
| `/etc/issue` | Mantener versión del paquete (N) — se regenera |
| `/etc/ssh/sshd_config` | Mantener tu versión (N) si la has personalizado, sino la nueva (Y) |
| `/etc/default/grub` | Mantener tu versión (N) si la has personalizado |
| Cualquier otro archivo en `/etc/proxmox-backup/*` | Mantener tu versión (N) |

**Tiempo:** 5 a 60 minutos dependiendo de la conexión y E/S.

### Paso 10 — Reinicio y verificación

```bash
systemctl reboot
```

Esperar 2–3 minutos. Reconectar por SSH y verificar:

```bash
# Versión nueva
proxmox-backup-manager versions
cat /etc/debian_version            # debe decir "13.x"
uname -r                            # kernel 6.14.x

# Servicios
systemctl status proxmox-backup-proxy.service proxmox-backup.service

# Datastores accesibles
proxmox-backup-manager datastore list
```

Limpiar caché del navegador (Ctrl+Shift+R) antes de abrir la UI web.

### Paso 11 — Desactivar modo mantenimiento

```bash
for ds in $(proxmox-backup-manager datastore list --output-format json | jq -r '.[].name'); do
  proxmox-backup-manager datastore update "$ds" --delete maintenance-mode
done
```

### Paso 12 — (Opcional) Modernizar formato de sources

```bash
apt modernize-sources
```

Convierte los `.list` antiguos al formato `.sources` deb822.

---

## 4. Validación post-upgrade

| Check | Comando | Resultado esperado |
|-------|---------|--------------------|
| Versión PBS | `proxmox-backup-manager versions` | `proxmox-backup-server 4.x.x` |
| Versión Debian | `cat /etc/debian_version` | `13.x` |
| Kernel | `uname -r` | `6.14.x` |
| Servicios | `systemctl is-active proxmox-backup{,-proxy}` | `active` en ambos |
| UI web | Navegador → `https://<ip>:8007` | Login OK |
| Datastores | `proxmox-backup-manager datastore list` | Todos OK |
| Test backup | Disparar un backup manual desde un cliente PVE | Completa sin error |
| Test verify | `proxmox-backup-manager verify <datastore>` | Sin errores nuevos |

**Realizar al menos un backup nuevo y un verify completo antes de eliminar el snapshot OVH del Paso 1.**

---

## 5. Script de automatización

El repositorio incluye `pbs-upgrade-3-to-4.sh` que automatiza los pasos **4 a 10** (todo salvo el snapshot, el `tmux` y el `reboot` final, que se confirman manualmente). Ver [scripts/README.md](README.md) sección `pbs-upgrade-3-to-4.sh`.

**Uso resumido:**

```bash
# 1. Hacer snapshot manual en panel OVH (CRÍTICO, no automatizable)
# 2. Conectarse vía tmux
tmux new -s pbs-upgrade

# 3. Descargar y revisar
wget https://raw.githubusercontent.com/sysamu/proxmox-utils/main/scripts/pbs-upgrade-3-to-4.sh
chmod +x pbs-upgrade-3-to-4.sh

# 4. Ejecutar — el script pedirá confirmaciones en cada fase
sudo ./pbs-upgrade-3-to-4.sh

# 5. Reiniciar manualmente cuando el script lo indique
systemctl reboot

# 6. Post-reboot, ejecutar con --post para validación final
sudo ./pbs-upgrade-3-to-4.sh --post
```

---

## 6. Plan de rollback

| Síntoma | Acción |
|---------|--------|
| `dist-upgrade` falla a mitad y la VM sigue arrancando | Intentar `apt -f install` y `dpkg --configure -a`. Si no se resuelve, restaurar snapshot. |
| Servicio `proxmox-backup-proxy` no levanta tras reboot | Revisar `journalctl -u proxmox-backup-proxy -b`. Si es config corrupta, restaurar `/etc/proxmox-backup` desde el tarball. |
| VM no arranca tras reboot | Consola OVH → revisar mensajes. Si no recupera, **restaurar snapshot OVH** (crear instancia nueva desde snapshot). |
| Datastores no aparecen | Verificar montajes (`mount -a`, `/etc/fstab`). Restaurar `/etc/proxmox-backup/datastore.cfg` desde tarball. |
| UI web 502/503 | `systemctl restart proxmox-backup-proxy`. Si persiste, ver logs y `pveversion` (PBS no, pero el equivalente). |

**Rollback completo (catastrófico):**

1. Panel OVH → Public Cloud → Instances → **Create instance from snapshot**.
2. Asignar la misma IP flotante (o actualizar DNS / clientes PVE).
3. Validar que los datastores siguen montados (si están en volúmenes separados que no fueron parte del snapshot, deberían intactos).

---

## 7. Notas específicas de OVH Public Cloud B3-16

- **Disco raíz:** típicamente 100 GB en volumen raíz local. Los datastores PBS suelen vivir en **Block Storage adicional** montado en `/mnt/datastore/...`. El snapshot OVH **NO incluye** los volúmenes block storage adjuntos — solo el disco raíz. Esto está bien para rollback del SO, pero **el contenido de los datastores se conserva en su volumen** independientemente.
- **Red:** interfaces `ens3`/`eth0` con driver virtio, no cambian de nombre entre kernels.
- **Acceso fuera de banda:** Panel OVH → Instance → "..." → **Console**. Usa esta consola si SSH se rompe.
- **Sin GRUB chainload custom:** OVH usa GRUB estándar sobre el disco raíz, no requiere `ESP_sync.sh`.

---

## 8. Referencias

- Upgrade oficial: <https://pbs.proxmox.com/wiki/index.php/Upgrade_from_3_to_4>
- Roadmap PBS 4.0: <https://pbs.proxmox.com/wiki/index.php/Roadmap>
- Debian Trixie release notes: <https://www.debian.org/releases/trixie/releasenotes>
- Repositorio de scripts: `proxmox-utils/scripts/`

---

## Changelog

| Fecha | Autor | Cambio |
|-------|-------|--------|
| 2026-05-28 | sysamu | Versión inicial para PBS 3.4.6 → 4.2 en OVH B3-16 |
