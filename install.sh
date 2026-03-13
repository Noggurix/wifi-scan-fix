#!/usr/bin/env bash
set -euo pipefail

sudo -n true 2>/dev/null || sudo -v

SERVICE_NAME="wifi-scan-fix.service"
WATCHER_NAME="wifi-scan-fix-watcher"
HELPER_NAME="wifi-scan-fix-helper"
SUDOERS_TEMPLATE_NAME="wifi-scan-fix.sudoers"
SUDOERS_NAME="wifi-scan-fix"

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
USER_NAME="${TARGET_USER:-${SUDO_USER:-${USER:-}}}"

require_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "Error: mandatory command not found: $1"
		exit 1
	fi
}

escape_sed_replacement() {
	printf '%s' "$1" | sed -e 's/[&|]/\\&/g'
}

require_cmd id
require_cmd getent
require_cmd cut
require_cmd nmcli
require_cmd iw
if [[ "${SKIP_SYSTEMD:-0}" != "1" ]]; then
	require_cmd systemctl
fi
require_cmd install
require_cmd sed
require_cmd awk
require_cmd grep
require_cmd mktemp
require_cmd visudo
require_cmd rm

if [[ -z "$USER_NAME" ]]; then
	echo "Error: unable to resolve target user."
	exit 1
fi

USER_UID="$(id -u "$USER_NAME")"
USER_GROUP="$(id -gn "$USER_NAME")"
XDG_RUNTIME_DIR="/run/user/$USER_UID"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"

tmp_watcher=""
tmp_helper=""
tmp_sudoers=""
tmp_service=""

cleanup() {
	rm -f "$tmp_watcher" "$tmp_helper" "$tmp_sudoers" "$tmp_service"
}
trap cleanup EXIT

if [[ "$USER_NAME" == "root" ]]; then
	echo "Error: target user resolved to root."
	echo "Run this installer as your regular user (with sudo privileges)."
	exit 1
fi

if [[ -z "${USER_HOME:-}" || ! -d "$USER_HOME" ]]; then
	echo "Error: cannot identify user HOME."
	exit 1
fi

if [[ -f "/etc/sudoers.d/$SUDOERS_NAME" ]]; then
	echo "Warning: /etc/sudoers.d/$SUDOERS_NAME already exists and will be replaced."
fi

if [[ -f "$USER_HOME/.local/bin/$WATCHER_NAME" ]]; then
	echo "Info: existing watcher found, updating it."
fi

if [[ -f "/usr/local/bin/$HELPER_NAME" ]]; then
	echo "Info: existing root helper found, updating it."
fi

if [[ -f "$USER_HOME/.config/systemd/user/$SERVICE_NAME" ]]; then
	echo "Info: existing user service found, updating it."
fi

if [[ ! -f "$REPO_DIR/$WATCHER_NAME" ]]; then
	echo "Error: file not found: $REPO_DIR/$WATCHER_NAME"
	exit 1
fi

if [[ ! -f "$REPO_DIR/$HELPER_NAME" ]]; then
	echo "Error: file not found: $REPO_DIR/$HELPER_NAME"
	exit 1
fi

if [[ ! -f "$REPO_DIR/$SERVICE_NAME" ]]; then
	echo "Error: file not found: $REPO_DIR/$SERVICE_NAME"
	exit 1
fi

if [[ ! -f "$REPO_DIR/$SUDOERS_TEMPLATE_NAME" ]]; then
	echo "Error: file not found: $REPO_DIR/$SUDOERS_TEMPLATE_NAME"
	exit 1
fi

INTERFACE_NAME="${WIFI_INTERFACE:-$(iw dev | awk '$1=="Interface"{print $2; exit}')}"

if [[ -z "${INTERFACE_NAME:-}" ]]; then
	if [[ "${ALLOW_MISSING_WIFI_INTERFACE:-0}" == "1" ]]; then
		echo "Warning: no Wi-Fi interface detected. Using placeholder interface for installer test."
		INTERFACE_NAME="wlan0"
	else
		echo "Error: unable to detect Wi-Fi interface."
		echo "'iw dev' output:"
		iw dev || true
		exit 1
	fi
fi

if [[ "${SKIP_SYSTEMD:-0}" != "1" ]]; then
	if [[ ! -d "$XDG_RUNTIME_DIR" ]]; then
		echo "Error: user systemd runtime not found: $XDG_RUNTIME_DIR"
		echo "Please run this installer from inside the target user's active session."
		exit 1
	fi

	if ! sudo -u "$USER_NAME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user show-environment >/dev/null 2>&1; then
		echo "Error: user systemd instance is not available."
		echo "Please run this installer from inside the target user's active graphical session."
		exit 1
	fi
fi

if [[ "${ALLOW_MISSING_WIFI_INTERFACE:-0}" != "1" ]]; then
	if ! iw dev "$INTERFACE_NAME" info >/dev/null 2>&1; then
		echo "Error: detected interface does not exist: $INTERFACE_NAME"
		exit 1
	fi
fi

echo "[1/7] Detected interface: $INTERFACE_NAME"

ESCAPED_INTERFACE_NAME="$(escape_sed_replacement "$INTERFACE_NAME")"
ESCAPED_USER_NAME="$(escape_sed_replacement "$USER_NAME")"
ESCAPED_USER_HOME="$(escape_sed_replacement "$USER_HOME")"
ESCAPED_WATCHER_NAME="$(escape_sed_replacement "$WATCHER_NAME")"

sudo install -d -m 755 -o "$USER_NAME" -g "$USER_GROUP" "$USER_HOME/.local/bin"
sudo install -d -m 755 -o "$USER_NAME" -g "$USER_GROUP" "$USER_HOME/.config/systemd/user"

echo "[2/7] Installing watcher script..."
tmp_watcher="$(mktemp)"
sed "s|__WIFI_INTERFACE__|$ESCAPED_INTERFACE_NAME|g" \
	"$REPO_DIR/$WATCHER_NAME" > "$tmp_watcher"
sudo install -m 755 -o "$USER_NAME" -g "$USER_GROUP" "$tmp_watcher" "$USER_HOME/.local/bin/$WATCHER_NAME"

echo "[3/7] Installing root scan helper..."
tmp_helper="$(mktemp)"
sed "s|__WIFI_INTERFACE__|$ESCAPED_INTERFACE_NAME|g" \
	"$REPO_DIR/$HELPER_NAME" > "$tmp_helper"
sudo install -m 755 -o root -g root "$tmp_helper" "/usr/local/bin/$HELPER_NAME"

echo "[4/7] Installing sudoers rule..."
tmp_sudoers="$(mktemp)"
sed "s|__TARGET_USER__|$ESCAPED_USER_NAME|g" \
	"$REPO_DIR/$SUDOERS_TEMPLATE_NAME" > "$tmp_sudoers"
sudo install -m 440 -o root -g root "$tmp_sudoers" "/etc/sudoers.d/$SUDOERS_NAME"
sudo visudo -cf "/etc/sudoers.d/$SUDOERS_NAME" >/dev/null

echo "[5/7] Installing systemd service..."
tmp_service="$(mktemp)"
sed \
	-e "s|__USER_HOME__|$ESCAPED_USER_HOME|g" \
	-e "s|__WATCHER_NAME__|$ESCAPED_WATCHER_NAME|g" \
	"$REPO_DIR/$SERVICE_NAME" > "$tmp_service"
sudo install -m 644 -o "$USER_NAME" -g "$USER_GROUP" "$tmp_service" "$USER_HOME/.config/systemd/user/$SERVICE_NAME"

if [[ "${SKIP_SYSTEMD:-0}" != "1" ]]; then
	echo "[6/7] Reloading user systemd..."
	sudo -u "$USER_NAME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user daemon-reload

	if sudo -u "$USER_NAME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user is-enabled "$SERVICE_NAME" >/dev/null 2>&1; then
		echo "[7/7] Service already enabled. Restarting..."
		sudo -u "$USER_NAME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user restart "$SERVICE_NAME"
	else
		echo "[7/7] Enabling and starting service..."
		sudo -u "$USER_NAME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
			systemctl --user enable --now "$SERVICE_NAME"
	fi
else
	echo "[6/7] Skipping user systemd reload (SKIP_SYSTEMD=1)"
	echo "[7/7] Skipping service enable/start (SKIP_SYSTEMD=1)"
fi

echo
echo "Install completed."
echo "Target user: $USER_NAME"
echo "Wi-Fi interface: $INTERFACE_NAME"
echo
echo "Next step:"
if [[ "${SKIP_SYSTEMD:-0}" == "1" ]]; then
	echo "  TARGET_USER=$USER_NAME SKIP_SYSTEMD=1 ./verify.sh"
else
	echo "  ./verify.sh"
	echo
	echo "Useful commands:"
	echo "  systemctl --user status $SERVICE_NAME"
	echo "  journalctl --user -u $SERVICE_NAME -b"
fi