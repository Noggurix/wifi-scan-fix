#!/usr/bin/env bash
set -euo pipefail

sudo -n true 2>/dev/null || sudo -v

SERVICE_NAME="wifi-scan-fix.service"
WATCHER_NAME="wifi-scan-fix-watcher"
HELPER_NAME="wifi-scan-fix-helper"
SUDOERS_NAME="wifi-scan-fix"

USER_NAME="${TARGET_USER:-${SUDO_USER:-${USER:-}}}"

require_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "Error: mandatory command not found: $1"
		exit 1
	fi
}

remove_path() {
	local path="$1"
	local owner="$2"

	if [[ "$owner" == "root" ]]; then
		if ! sudo test -e "$path" && ! sudo test -L "$path"; then
			echo "Info: not found, skipping: $path"
			return 0
		fi
		sudo rm -f -- "$path"
	else
		if [[ ! -e "$path" && ! -L "$path" ]]; then
			echo "Info: not found, skipping: $path"
			return 0
		fi
		rm -f -- "$path"
	fi

	echo "Info: removed: $path"
}

if [[ "${SKIP_SYSTEMD:-0}" != "1" ]]; then
	require_cmd systemctl
fi
require_cmd getent
require_cmd id
require_cmd cut
require_cmd rm

if [[ -z "$USER_NAME" ]]; then
	echo "Error: unable to resolve target user."
	exit 1
fi

if [[ "$USER_NAME" == "root" ]]; then
	echo "Error: target user resolved to root."
	echo "Run this uninstaller as your regular user (with sudo privileges)."
	exit 1
fi

USER_UID="$(id -u "$USER_NAME")"
XDG_RUNTIME_DIR="/run/user/$USER_UID"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"

if [[ -z "${USER_HOME:-}" || ! -d "$USER_HOME" ]]; then
	echo "Error: cannot identify user HOME."
	exit 1
fi

USER_SYSTEMD_READY=false
if [[ "${SKIP_SYSTEMD:-0}" != "1" ]]; then
	if [[ -d "$XDG_RUNTIME_DIR" ]] && \
		sudo -u "$USER_NAME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
		systemctl --user show-environment >/dev/null 2>&1; then
		USER_SYSTEMD_READY=true
	fi
fi

echo "[1/6] Stopping and disabling service..."
if [[ "${SKIP_SYSTEMD:-0}" == "1" ]]; then
	echo "Info: skipping stop/disable (SKIP_SYSTEMD=1)."
elif "$USER_SYSTEMD_READY"; then
	if sudo -u "$USER_NAME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
		systemctl --user disable --now "$SERVICE_NAME" >/dev/null 2>&1; then
		echo "Info: service disabled and stopped."
	else
		echo "Info: service was not enabled/running."
	fi
else
	echo "Warning: user systemd runtime unavailable; skipping stop/disable."
fi

echo "[2/6] Removing user service files..."
remove_path "$USER_HOME/.config/systemd/user/$SERVICE_NAME" "user"
remove_path "$USER_HOME/.config/systemd/user/default.target.wants/$SERVICE_NAME" "user"

echo "[3/6] Removing watcher script..."
remove_path "$USER_HOME/.local/bin/$WATCHER_NAME" "user"

echo "[4/6] Removing root scan helper..."
remove_path "/usr/local/bin/$HELPER_NAME" "root"

echo "[5/6] Removing sudoers rule..."
remove_path "/etc/sudoers.d/$SUDOERS_NAME" "root"

echo "[6/6] Reloading user systemd..."
if [[ "${SKIP_SYSTEMD:-0}" == "1" ]]; then
	echo "Info: skipping daemon-reload (SKIP_SYSTEMD=1)."
elif "$USER_SYSTEMD_READY"; then
	sudo -u "$USER_NAME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user daemon-reload
	sudo -u "$USER_NAME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user reset-failed >/dev/null 2>&1 || true
else
	echo "Warning: user systemd runtime unavailable; skipping daemon-reload."
fi

echo
echo "Uninstall completed."
echo "Target user: $USER_NAME"
