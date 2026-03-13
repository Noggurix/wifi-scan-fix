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

require_cmd id
require_cmd getent
require_cmd cut
if [[ "${SKIP_SYSTEMD:-0}" != "1" ]]; then
	require_cmd systemctl
fi
require_cmd visudo

if [[ -z "$USER_NAME" ]]; then
	echo "Error: unable to resolve target user."
	exit 1
fi

if [[ "$USER_NAME" == "root" ]]; then
	echo "Error: target user resolved to root."
	echo "Run this verifier as your regular user (with sudo privileges)."
	exit 1
fi

USER_UID="$(id -u "$USER_NAME")"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"

if [[ -z "${USER_HOME:-}" || ! -d "$USER_HOME" ]]; then
	echo "Error: cannot identify user HOME."
	exit 1
fi

XDG_RUNTIME_DIR="/run/user/$USER_UID"

FAILED=0

check() {
	local name="$1"
	local path="$2"
	local owner="${3:-user}"

	if [[ "$owner" == "root" ]]; then
		if sudo test -e "$path" || sudo test -L "$path"; then
			echo "[OK] $name found: $path"
		else
			echo "[FAIL] $name missing: $path"
			FAILED=1
		fi
	else
		if [[ -e "$path" || -L "$path" ]]; then
			echo "[OK] $name found: $path"
		else
			echo "[FAIL] $name missing: $path"
			FAILED=1
		fi
	fi
}

echo "Checking installation for user: $USER_NAME"
echo

check "Watcher script" "$USER_HOME/.local/bin/$WATCHER_NAME"

check "User systemd service" \
"$USER_HOME/.config/systemd/user/$SERVICE_NAME"

if [[ "${SKIP_SYSTEMD:-0}" != "1" ]]; then
	check "Systemd enable symlink" \
	"$USER_HOME/.config/systemd/user/default.target.wants/$SERVICE_NAME"
fi
check "Root helper" \
"/usr/local/bin/$HELPER_NAME" "root"

check "Sudoers rule" \
"/etc/sudoers.d/$SUDOERS_NAME" "root"

echo

echo "Checking sudoers syntax..."

if sudo test -f "/etc/sudoers.d/$SUDOERS_NAME"; then
	if sudo visudo -cf "/etc/sudoers.d/$SUDOERS_NAME" >/dev/null 2>&1; then
		echo "[OK] sudoers syntax valid"
	else
		echo "[FAIL] sudoers syntax invalid"
		FAILED=1
	fi
else
	echo "[INFO] sudoers rule not installed"
fi

echo
echo "Checking systemd service..."

if [[ "${SKIP_SYSTEMD:-0}" == "1" ]]; then
	echo "[INFO] systemd checks skipped (SKIP_SYSTEMD=1)"
elif [[ -d "$XDG_RUNTIME_DIR" ]]; then
	if sudo -u "$USER_NAME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
		systemctl --user is-enabled "$SERVICE_NAME" >/dev/null 2>&1; then
		echo "[OK] systemd user service enabled"
	else
		echo "[INFO] systemd user service not enabled"
	fi

	if sudo -u "$USER_NAME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
		systemctl --user is-active "$SERVICE_NAME" >/dev/null 2>&1; then
		echo "[OK] systemd user service running"
	else
		echo "[INFO] systemd user service not running"
	fi
else
	echo "[INFO] user systemd runtime unavailable"
fi

echo
echo "Verification finished."
exit "$FAILED"
