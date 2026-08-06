#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(
	cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &&
		pwd
)"
WATCHER_SOURCE="$ROOT_DIR/wifi-scan-fix-watcher"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

require_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "Error: required test command not found: $1"
		exit 1
	fi
}

for command_name in bash grep mktemp sed timeout; do
	require_cmd "$command_name"
done

if [[ ! -f "$WATCHER_SOURCE" ]]; then
	echo "Error: watcher source not found: $WATCHER_SOURCE"
	exit 1
fi

bash -n "$WATCHER_SOURCE"

sed \
	-e 's|readonly INTERFACE="__WIFI_INTERFACE__"|readonly INTERFACE="wlan0"|' \
	-e 's|readonly POLL_INTERVAL=3|readonly POLL_INTERVAL=0.05|' \
	-e 's|readonly SCAN_RETRY_INTERVAL=2|readonly SCAN_RETRY_INTERVAL=0.05|' \
	-e 's|sleep 1|sleep 0.05|' \
	-e "s|/usr/bin/nmcli|$TEST_DIR/nmcli|g" \
	-e "s|/usr/bin/sudo|$TEST_DIR/sudo|g" \
	"$WATCHER_SOURCE" >"$TEST_DIR/watcher"

chmod +x "$TEST_DIR/watcher"

assert_count() {
	local expected="$1"
	local pattern="$2"
	local file="$3"
	local actual

	actual="$(grep -F -c "$pattern" "$file" || true)"

	if [[ "$actual" != "$expected" ]]; then
		echo "FAIL: expected $expected occurrence(s) of:"
		echo "  $pattern"
		echo "Found: $actual"
		echo
		cat "$file"
		exit 1
	fi
}

run_watcher() {
	local output="$1"
	local duration="${2:-1.5s}"
	local status

	set +e
	timeout --signal=TERM "$duration" "$TEST_DIR/watcher" \
		>"$output" 2>&1
	status=$?
	set -e

	case "$status" in
	124 | 143)
		;;
	*)
		echo "FAIL: watcher exited unexpectedly with status=$status"
		cat "$output"
		exit 1
		;;
	esac
}

echo "Test 1: state query failure and recovery"

cat >"$TEST_DIR/nmcli" <<'MOCK'
#!/usr/bin/env bash
set -u

counter_file="${MOCK_COUNTER:?}"
count=0

if [[ -f "$counter_file" ]]; then
	read -r count <"$counter_file"
fi

count=$((count + 1))
printf '%s\n' "$count" >"$counter_file"

case "$count" in
1)
	exit 10
	;;
2)
	printf '%s\n' "unexpected-state"
	;;
*)
	printf '%s\n' "enabled"
	;;
esac
MOCK

cat >"$TEST_DIR/sudo" <<'MOCK'
#!/usr/bin/env bash
set -u

printf 'scan\n' >>"${MOCK_SCAN_LOG:?}"
exit 0
MOCK

chmod +x "$TEST_DIR/nmcli" "$TEST_DIR/sudo"

printf '0\n' >"$TEST_DIR/counter"
: >"$TEST_DIR/scan.log"

export MOCK_COUNTER="$TEST_DIR/counter"
export MOCK_SCAN_LOG="$TEST_DIR/scan.log"

run_watcher "$TEST_DIR/recovery-output"

assert_count 1 \
	"failed to query Wi-Fi state" \
	"$TEST_DIR/recovery-output"

assert_count 1 \
	"Wi-Fi state query recovered state=enabled" \
	"$TEST_DIR/recovery-output"

assert_count 1 \
	"Wi-Fi enabled; triggering scan interface=wlan0" \
	"$TEST_DIR/recovery-output"

assert_count 1 \
	"scan completed interface=wlan0 attempt=1" \
	"$TEST_DIR/recovery-output"

assert_count 1 \
	"scan" \
	"$TEST_DIR/scan.log"

echo "PASS: repeated query failures produced one warning and one recovery scan."

echo
echo "Test 2: transient helper failure"

cat >"$TEST_DIR/nmcli" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "enabled"
MOCK

cat >"$TEST_DIR/sudo" <<'MOCK'
#!/usr/bin/env bash
set -u

counter_file="${MOCK_COUNTER:?}"
count=0

if [[ -f "$counter_file" ]]; then
	read -r count <"$counter_file"
fi

count=$((count + 1))
printf '%s\n' "$count" >"$counter_file"

if ((count == 1)); then
	exit 42
fi

exit 0
MOCK

chmod +x "$TEST_DIR/nmcli" "$TEST_DIR/sudo"
printf '0\n' >"$TEST_DIR/counter"

run_watcher "$TEST_DIR/transient-output"

assert_count 1 \
	"scan failed interface=wlan0 exit=42 attempt=1/3; retrying" \
	"$TEST_DIR/transient-output"

assert_count 1 \
	"scan completed interface=wlan0 attempt=2" \
	"$TEST_DIR/transient-output"

assert_count 0 \
	"giving up until next Wi-Fi enable" \
	"$TEST_DIR/transient-output"

if [[ "$(cat "$TEST_DIR/counter")" != "2" ]]; then
	echo "FAIL: expected exactly two helper executions."
	exit 1
fi

echo "PASS: watcher recovered on the second scan attempt."

echo
echo "Test 3: persistent helper failure"

cat >"$TEST_DIR/sudo" <<'MOCK'
#!/usr/bin/env bash
set -u

counter_file="${MOCK_COUNTER:?}"
count=0

if [[ -f "$counter_file" ]]; then
	read -r count <"$counter_file"
fi

count=$((count + 1))
printf '%s\n' "$count" >"$counter_file"

exit 42
MOCK

chmod +x "$TEST_DIR/sudo"
printf '0\n' >"$TEST_DIR/counter"

run_watcher "$TEST_DIR/persistent-output"

assert_count 1 \
	"scan failed interface=wlan0 exit=42 attempt=1/3; retrying" \
	"$TEST_DIR/persistent-output"

assert_count 1 \
	"scan failed interface=wlan0 exit=42 attempt=2/3; retrying" \
	"$TEST_DIR/persistent-output"

assert_count 1 \
	"scan failed interface=wlan0 exit=42 attempts=3; giving up until next Wi-Fi enable" \
	"$TEST_DIR/persistent-output"

assert_count 0 \
	"scan completed interface=wlan0" \
	"$TEST_DIR/persistent-output"

if [[ "$(cat "$TEST_DIR/counter")" != "3" ]]; then
	echo "FAIL: expected exactly three helper executions."
	exit 1
fi

echo "PASS: watcher stopped retrying after three failures."

echo
echo "All watcher tests passed."
