#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="wifi-scan-fix.service"
WATCHER_NAME="wifi-scan-fix-watcher"
HELPER_NAME="wifi-scan-fix-helper"
SUDOERS_TEMPLATE_NAME="wifi-scan-fix.sudoers"
SUDOERS_NAME="wifi-scan-fix"

REPO_DIR="$(
	cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
		pwd
)"

USER_NAME="${TARGET_USER:-${SUDO_USER:-${USER:-}}}"
SKIP_SYSTEMD="${SKIP_SYSTEMD:-0}"

require_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "Error: mandatory command not found: $1"
		exit 1
	fi
}

escape_sed_replacement() {
	printf '%s' "$1" | sed -e 's/[&|]/\\&/g'
}

for command_name in \
	sudo id getent cut bash cmp grep sed awk stat readlink \
	mktemp rm dirname visudo
do
	require_cmd "$command_name"
done

if [[ "$SKIP_SYSTEMD" != "1" ]]; then
	require_cmd systemctl
fi

sudo -n true 2>/dev/null || sudo -v

if [[ -z "$USER_NAME" ]]; then
	echo "Error: unable to resolve target user."
	exit 1
fi

if [[ "$USER_NAME" == "root" ]]; then
	echo "Error: target user resolved to root."
	echo "Run this verifier as your regular user (with sudo privileges)."
	exit 1
fi

if ! id "$USER_NAME" >/dev/null 2>&1; then
	echo "Error: target user does not exist: $USER_NAME"
	exit 1
fi

USER_UID="$(id -u "$USER_NAME")"
USER_GROUP="$(id -gn "$USER_NAME")"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
XDG_RUNTIME_DIR="/run/user/$USER_UID"

if [[ -z "${USER_HOME:-}" || ! -d "$USER_HOME" ]]; then
	echo "Error: cannot identify user HOME."
	exit 1
fi

WATCHER_PATH="$USER_HOME/.local/bin/$WATCHER_NAME"
SERVICE_PATH="$USER_HOME/.config/systemd/user/$SERVICE_NAME"
ENABLE_LINK="$USER_HOME/.config/systemd/user/default.target.wants/$SERVICE_NAME"
HELPER_PATH="/usr/local/bin/$HELPER_NAME"
SUDOERS_PATH="/etc/sudoers.d/$SUDOERS_NAME"

for source_file in \
	"$REPO_DIR/$WATCHER_NAME" \
	"$REPO_DIR/$HELPER_NAME" \
	"$REPO_DIR/$SERVICE_NAME" \
	"$REPO_DIR/$SUDOERS_TEMPLATE_NAME"
do
	if [[ ! -f "$source_file" ]]; then
		echo "Error: repository file not found: $source_file"
		exit 1
	fi
done

TEMP_DIR="$(mktemp -d)"

cleanup() {
	rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

FAILED=0

ok() {
	echo "[OK] $*"
}

info() {
	echo "[INFO] $*"
}

fail() {
	echo "[FAIL] $*"
	FAILED=1
}

check_regular_file() {
	local name="$1"
	local path="$2"

	if sudo test -f "$path"; then
		ok "$name found: $path"
	else
		fail "$name missing or not a regular file: $path"
	fi
}

check_symlink() {
	local name="$1"
	local path="$2"

	if sudo test -L "$path"; then
		ok "$name found: $path"
	else
		fail "$name missing or not a symbolic link: $path"
	fi
}

check_metadata() {
	local name="$1"
	local path="$2"
	local expected_owner="$3"
	local expected_mode="$4"
	local actual_owner
	local actual_mode

	if ! sudo test -e "$path"; then
		return
	fi

	actual_owner="$(sudo stat -c '%U:%G' -- "$path")"
	actual_mode="$(sudo stat -c '%a' -- "$path")"

	if [[ "$actual_owner" == "$expected_owner" ]]; then
		ok "$name owner is $actual_owner"
	else
		fail "$name owner is $actual_owner; expected $expected_owner"
	fi

	if [[ "$actual_mode" == "$expected_mode" ]]; then
		ok "$name mode is $actual_mode"
	else
		fail "$name mode is $actual_mode; expected $expected_mode"
	fi
}

check_executable() {
	local name="$1"
	local path="$2"

	if ! sudo test -e "$path"; then
		return
	fi

	if sudo test -x "$path"; then
		ok "$name is executable"
	else
		fail "$name is not executable"
	fi
}

check_no_placeholders() {
	local name="$1"
	local path="$2"

	if ! sudo test -f "$path"; then
		return
	fi

	if sudo grep -Eq '__[A-Z0-9_]+__' "$path"; then
		fail "$name still contains an unsubstituted placeholder"
	else
		ok "$name contains no unresolved placeholders"
	fi
}

check_bash_syntax() {
	local name="$1"
	local path="$2"

	if ! sudo test -f "$path"; then
		return
	fi

	if sudo bash -n "$path"; then
		ok "$name Bash syntax is valid"
	else
		fail "$name Bash syntax is invalid"
	fi
}

check_exact_content() {
	local name="$1"
	local expected="$2"
	local installed="$3"

	if ! sudo test -f "$installed"; then
		return
	fi

	if sudo cmp -s -- "$expected" "$installed"; then
		ok "$name matches the repository template"
	else
		fail "$name differs from the rendered repository template"
	fi
}

run_user_systemctl() {
	sudo -u "$USER_NAME" \
		XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
		systemctl --user "$@"
}

echo "Checking installation for user: $USER_NAME"
echo

echo "Checking installed files..."

check_regular_file "Watcher script" "$WATCHER_PATH"
check_regular_file "User systemd service" "$SERVICE_PATH"
check_regular_file "Root helper" "$HELPER_PATH"
check_regular_file "Sudoers rule" "$SUDOERS_PATH"

if [[ "$SKIP_SYSTEMD" != "1" ]]; then
	check_symlink "Systemd enable symlink" "$ENABLE_LINK"
fi

echo
echo "Checking ownership and permissions..."

check_metadata \
	"Watcher script" \
	"$WATCHER_PATH" \
	"$USER_NAME:$USER_GROUP" \
	"755"

check_metadata \
	"User systemd service" \
	"$SERVICE_PATH" \
	"$USER_NAME:$USER_GROUP" \
	"644"

check_metadata \
	"Root helper" \
	"$HELPER_PATH" \
	"root:root" \
	"755"

check_metadata \
	"Sudoers rule" \
	"$SUDOERS_PATH" \
	"root:root" \
	"440"

check_executable "Watcher script" "$WATCHER_PATH"
check_executable "Root helper" "$HELPER_PATH"

echo
echo "Checking installed file syntax..."

check_bash_syntax "Watcher script" "$WATCHER_PATH"
check_bash_syntax "Root helper" "$HELPER_PATH"

if sudo test -f "$SUDOERS_PATH"; then
	if sudo visudo -cf "$SUDOERS_PATH" >/dev/null 2>&1; then
		ok "sudoers syntax is valid"
	else
		fail "sudoers syntax is invalid"
	fi
fi

echo
echo "Checking template substitutions..."

check_no_placeholders "Watcher script" "$WATCHER_PATH"
check_no_placeholders "User systemd service" "$SERVICE_PATH"
check_no_placeholders "Root helper" "$HELPER_PATH"
check_no_placeholders "Sudoers rule" "$SUDOERS_PATH"

WATCHER_INTERFACE=""
HELPER_INTERFACE=""

if sudo test -f "$WATCHER_PATH"; then
	WATCHER_INTERFACE="$(
		sudo sed -n \
			's/^[[:space:]]*readonly INTERFACE="\([^"]*\)"$/\1/p' \
			"$WATCHER_PATH" |
			sed -n '1p'
	)"
fi

if sudo test -f "$HELPER_PATH"; then
	HELPER_INTERFACE="$(
		sudo awk '
			$1 == "/usr/bin/iw" &&
			$2 == "dev" &&
			$4 == "scan" {
				print $3
				exit
			}
		' "$HELPER_PATH"
	)"
fi

if [[ -n "$WATCHER_INTERFACE" ]]; then
	ok "watcher interface is $WATCHER_INTERFACE"
else
	fail "unable to determine interface from installed watcher"
fi

if [[ -n "$HELPER_INTERFACE" ]]; then
	ok "helper interface is $HELPER_INTERFACE"
else
	fail "unable to determine interface from installed helper"
fi

if [[ -n "$WATCHER_INTERFACE" && -n "$HELPER_INTERFACE" ]]; then
	if [[ "$WATCHER_INTERFACE" == "$HELPER_INTERFACE" ]]; then
		ok "watcher and helper use the same interface"
	else
		fail "interface mismatch: watcher=$WATCHER_INTERFACE helper=$HELPER_INTERFACE"
	fi
fi

echo
echo "Checking installed contents..."

ESCAPED_USER_NAME="$(escape_sed_replacement "$USER_NAME")"
ESCAPED_USER_HOME="$(escape_sed_replacement "$USER_HOME")"
ESCAPED_WATCHER_NAME="$(escape_sed_replacement "$WATCHER_NAME")"

EXPECTED_SERVICE="$TEMP_DIR/$SERVICE_NAME"
EXPECTED_SUDOERS="$TEMP_DIR/$SUDOERS_NAME"

sed \
	-e "s|__USER_HOME__|$ESCAPED_USER_HOME|g" \
	-e "s|__WATCHER_NAME__|$ESCAPED_WATCHER_NAME|g" \
	"$REPO_DIR/$SERVICE_NAME" >"$EXPECTED_SERVICE"

sed \
	"s|__TARGET_USER__|$ESCAPED_USER_NAME|g" \
	"$REPO_DIR/$SUDOERS_TEMPLATE_NAME" >"$EXPECTED_SUDOERS"

check_exact_content \
	"User systemd service" \
	"$EXPECTED_SERVICE" \
	"$SERVICE_PATH"

check_exact_content \
	"Sudoers rule" \
	"$EXPECTED_SUDOERS" \
	"$SUDOERS_PATH"

INTERFACE_NAME="${WATCHER_INTERFACE:-$HELPER_INTERFACE}"

if [[ -n "$INTERFACE_NAME" ]]; then
	ESCAPED_INTERFACE_NAME="$(escape_sed_replacement "$INTERFACE_NAME")"

	EXPECTED_WATCHER="$TEMP_DIR/$WATCHER_NAME"
	EXPECTED_HELPER="$TEMP_DIR/$HELPER_NAME"

	sed \
		"s|__WIFI_INTERFACE__|$ESCAPED_INTERFACE_NAME|g" \
		"$REPO_DIR/$WATCHER_NAME" >"$EXPECTED_WATCHER"

	sed \
		"s|__WIFI_INTERFACE__|$ESCAPED_INTERFACE_NAME|g" \
		"$REPO_DIR/$HELPER_NAME" >"$EXPECTED_HELPER"

	check_exact_content \
		"Watcher script" \
		"$EXPECTED_WATCHER" \
		"$WATCHER_PATH"

	check_exact_content \
		"Root helper" \
		"$EXPECTED_HELPER" \
		"$HELPER_PATH"
else
	info "content comparison for watcher and helper skipped: interface unavailable"
fi

echo
echo "Checking sudo authorization..."

if sudo test -f "$SUDOERS_PATH"; then
	if sudo -u "$USER_NAME" \
		sudo -n -l "$HELPER_PATH" >/dev/null 2>&1
	then
		ok "target user has passwordless access to the helper"
	else
		fail "target user cannot invoke the helper through passwordless sudo"
	fi
fi

echo
echo "Checking systemd service..."

if [[ "$SKIP_SYSTEMD" == "1" ]]; then
	info "systemd checks skipped (SKIP_SYSTEMD=1)"
elif [[ ! -d "$XDG_RUNTIME_DIR" ]]; then
	fail "user systemd runtime unavailable: $XDG_RUNTIME_DIR"
elif ! run_user_systemctl show-environment >/dev/null 2>&1; then
	fail "user systemd instance is unavailable"
else
	if run_user_systemctl is-enabled "$SERVICE_NAME" >/dev/null 2>&1; then
		ok "systemd user service is enabled"
	else
		fail "systemd user service is not enabled"
	fi

	if run_user_systemctl is-active "$SERVICE_NAME" >/dev/null 2>&1; then
		ok "systemd user service is running"
	else
		fail "systemd user service is not running"
	fi

	LOADED_FRAGMENT="$(
		run_user_systemctl show \
			--property=FragmentPath \
			--value \
			"$SERVICE_NAME" 2>/dev/null ||
			true
	)"

	EXPECTED_FRAGMENT="$(
		readlink -f "$SERVICE_PATH" 2>/dev/null ||
			true
	)"

	if [[ -z "$EXPECTED_FRAGMENT" ]]; then
		fail "unable to resolve the installed service file"
	elif [[ -n "$LOADED_FRAGMENT" && "$LOADED_FRAGMENT" == "$EXPECTED_FRAGMENT" ]]; then
		ok "systemd loaded the expected service file"
	else
		fail "systemd loaded an unexpected service file: ${LOADED_FRAGMENT:-none}"
	fi

	NEED_RELOAD="$(
		run_user_systemctl show \
			--property=NeedDaemonReload \
			--value \
			"$SERVICE_NAME" 2>/dev/null ||
			true
	)"

	if [[ "$NEED_RELOAD" == "no" ]]; then
		ok "systemd daemon reload is not pending"
	else
		fail "systemd reports that a daemon reload is required"
	fi

	if sudo test -L "$ENABLE_LINK"; then
		ENABLE_TARGET="$(sudo readlink -f "$ENABLE_LINK" || true)"
		SERVICE_TARGET="$(sudo readlink -f "$SERVICE_PATH" || true)"

		if [[ -n "$ENABLE_TARGET" && "$ENABLE_TARGET" == "$SERVICE_TARGET" ]]; then
			ok "enable symlink points to the installed service"
		else
			fail "enable symlink points to an unexpected target"
		fi
	fi
fi

echo

if ((FAILED)); then
	echo "Verification failed."
else
	echo "Verification passed."
fi

exit "$FAILED"
