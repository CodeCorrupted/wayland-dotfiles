#!/usr/bin/env bash
# ============================================================
# Backup con restic al repo local del servidor vía SFTP,
# a través de WireGuard.
# ============================================================

set -euo pipefail

# --- Configuración (Constantes de solo lectura) ---
readonly HOME="/home/arc/"
readonly WG_INTERFACE="wg0"
readonly SERVER_IP="10.0.0.1"
readonly SERVER="delfos"
readonly LOCAL_REPO="/home/apolo/backups/restic-local"
readonly RESTIC_REPO="sftp:${SERVER}:${LOCAL_REPO}"
RESTIC_PASSWORD_FILE="$HOME/.config/restic/local-pass"
readonly EXCLUDE_FILE="$HOME/.restic-excludes"

# Umbral minimo de almacenamiento requerido en el servidor (en GB)
readonly MIN_FREE_SPACE_GB=10
readonly MIN_FREE_SPACE_KB=$((MIN_FREE_SPACE_GB * 1024 * 1024))

# Ubicación de logs siguiendo el estándar XDG Base Directory
readonly LOG_DIR="$HOME/.local/state/restic"
readonly LOG_FILE="$LOG_DIR/backup.log"

# Rutas a respaldar declaradas como ARRAY para prevenir errores de espacio/caracteres
readonly BACKUP_PATHS=(
	"$HOME/Documents"
	"$HOME/Pictures"
	"$HOME/Games"
	"$HOME/.config/retroarch/saves/"
)

# Rutas de carpetas pesadas a respaldar
readonly HEAVY_BACKUP_PATHS=(
	"$HOME/Music"
	"$HOME/Games/Legend_of_Zelda_Twilight_Princess"
	"$HOME/Games/Gamecube"
)

# Garantizar que el directorio para el log exista
mkdir -p "$LOG_DIR"

# --- Funciones ---
log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Notificación de escritorio usando notify-send estándar
notificar() {
	local urgencia="$1" # low, normal, critical
	local titulo="$2"
	local mensaje="$3"
	local icono="${4:-dialog-information}"

	notify-send -u "$urgencia" \
		-a "Restic Bakcup" \
		-i "$icono" \
		"$titulo" "$mensaje" 2>/dev/null || true
}

cleanup() {
	log "Bajando VPN ($WG_INTERFACE)..."
	sudo -n wg-quick down "$WG_INTERFACE" 2>/dev/null || true
}

# Manejador automático para errores no atrapados
on_error() {
	local linea="$1"
	log "ERROR CRÍTICO: El script falló inesperadamente en la línea $linea."
	notificar "critical" "Error en Backup Restic" "El proceso falló en la línea $linea. Revisa el log." "dialog-error"
}

# --- Registro de Trampas (Traps) ---
trap cleanup EXIT
trap 'on_error $LINENO' ERR

# --- Inicio del Proceso ---
log "=== Iniciando backup ==="
notificar "low" "Backup Restic" "Iniciando respaldo SFTP en segundo plano..." "drive-harddisk"

# 1. Levantar VPN (tolerando si ya estaba activa)
log "Levantando VPN ($WG_INTERFACE)..."
sudo -n wg-quick up "$WG_INTERFACE" 2>/dev/null || log "Nota: La interfaz $WG_INTERFACE ya podría estar activa."

# 2. Esperar a que el servidor sea alcanzable
log "Esperando conectividad con $SERVER_IP..."
servidor_alcanzable=false
for i in {1..10}; do
	if ping -c 1 -W 2 "$SERVER_IP" &>/dev/null; then
		log "Servidor alcanzable."
		servidor_alcanzable=true
		break
	fi
	sleep 2
done

if [[ "$servidor_alcanzable" == false ]]; then
	log "ERROR: No se pudo alcanzar el servidor $SERVER_IP tras 10 intentos."
	notificar "critical" "Error en Backup Restic" "Servidor $SERVER_IP inalcanzable." "dialog-error"
	exit 1
fi

# 3. Verificar espacio disponible en el repositorio remoto via SSH
log "Verificando el espacio libre en el destino ($LOCAL_REPO)..."
espacio_disponible_kb=$(ssh -o ConnectTimeout=5 "${SERVER}" "df -k '$LOCAL_REPO' | tail -n 1 | awk '{print \$4}'" 2>/dev/null || espacio_disponible_kb="")

# Validar que la respuesta solo contenga números
if [[ ! "$espacio_disponible_kb" =~ ^[0-9]+$ ]]; then
	log "ADVERTENCIA: No se pudo obtener el espacio libre del servidor (respuesta: '$espacio_disponible_kb'). Se asumira 0."
	espacio_disponible_kb=0
fi

espacio_disponible_gb=$((espacio_disponible_kb / 1024 / 1024))

if ((espacio_disponible_kb < MIN_FREE_SPACE_KB)); then
	log "ERROR: Espacio en disco insuficiente en el destino ($SERVER_IP)."
	log "Disponible: ${espacio_disponible_gb} GB | Requerido: ${MIN_FREE_SPACE_GB} GB."
	notificar "critical" \
		"Error: Espacio insuficiente" \
		"El servidor $SERVER_IP solo tiene ${espacio_disponible_gb} GB libres (Minimo: ${MIN_FREE_SPACE_GB} GB)" \
		"dialog-error"
	exit 1
fi

log "Espacio verificado: ${espacio_disponible_gb} GB disponibles (Mínimo requerido: ${MIN_FREE_SPACE_GB} GB)."

# 4. Exportar variables de entorno para restic
export RESTIC_REPOSITORY="$RESTIC_REPO"
export RESTIC_PASSWORD_FILE="$RESTIC_PASSWORD_FILE"

# 5. Ejecutar backup expandiendo el Array de forma segura
log "Ejecutando restic backups..."
if restic backup "${BACKUP_PATHS[@]}" --exclude-file="$EXCLUDE_FILE" --tag normal --verbose; then
	log "Backup de archivos ligeros completado con éxito."
else
	log "ERROR: Falló la ejecución del backup."
	notificar "critical" "Error en Backup Restic" "Fallo durante la copia con restic." "dialog-error"
	exit 1
fi

if restic backup "${HEAVY_BACKUP_PATHS[@]}" --tag grande --verbose; then
	log "Backup de archivos pesados completado con éxito."
else
	log "ERROR: Falló la ejecución del backup."
	notificar "critical" "Error en Backup Restic" "Fallo durante la copia con restic." "dialog-error"
	exit 1
fi

# 6. Política de retención en el repo local
log "Aplicando política de retención en el repo local..."
if restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune; then
	log "Política de retención aplicada correctamente."
else
	log "ADVERTENCIA: La retención finalizó con errores."
	notificar "critical" "Error en Backup Restic" "Fallo al aplicar política de retención." "dialog-error"
	exit 1
fi

# 7. Poda automática del log (mantiene las últimas 1,000 líneas si supera las 2,000)
if [[ -f "$LOG_FILE" ]] && (($(wc -l <"$LOG_FILE") > 2000)); then
	tail -n 1000 "$LOG_FILE" >"${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

log "=== Backup finalizado con éxito ==="
notificar "normal" "Backup Finalizado" "El respaldo SFTP se completó y purgó con éxito." "emblem-default"
