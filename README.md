# wifi-scan-fix

![GitHub License](https://img.shields.io/github/license/Noggurix/wifi-scan-fix?style=flat-square&color=%234e1f73) ![Platform](https://img.shields.io/badge/platform-linux-blue) ![Shell](https://img.shields.io/badge/language-shell-green)

A small Linux user-level service that automatically refreshes Wi-Fi scan results when nearby networks fail to appear after enabling Wi-Fi.

It is intended for cases where a manual `iw dev <interface> scan` causes the missing networks to appear.

A lightweight workaround for Linux Wi-Fi discovery issues that can be automated with `systemd --user` and a restricted helper.

## Contents

- [Problem](#problem)
- [Overview](#overview)
- [Requirements](#requirements)
- [Compatibility](#compatibility)
- [Quickstart](#quickstart)
- [Installation](#installation)
- [Verification](#verification)
- [Uninstallation](#uninstallation)
- [Configuration](#configuration)
- [How it works](#how-it-works)
- [Installed files](#installed-files)
- [Troubleshooting](#troubleshooting)
- [Testing](#testing)
- [License](#license)

---

## Problem

Some systems experience a Wi-Fi discovery issue where enabling Wi-Fi does not immediately show nearby networks.

In these cases, the wireless interface is functional, but the visible network list is not refreshed as expected. A manual scan such as:

```bash
sudo iw dev <interface> scan
```

can immediately make the missing networks appear.

This appears to be related to how scan results are refreshed or reused in the Wi-Fi stack, but the exact cause may vary depending on the driver, firmware, and system configuration.

This project automates that workaround.

---

## Overview

Once installed, the project:

1. Watches the Wi-Fi radio state with a user-level watcher script
2. Detects when Wi-Fi changes from disabled to enabled
3. Triggers a privileged scan when required
4. Retries transient scan failures up to three times
5. Allows NetworkManager to see the refreshed scan results

As a result, affected systems can refresh visible Wi-Fi networks immediately after the radio is enabled, without requiring a manual scan.

The project automates a pragmatic workaround that proved reliable in the tested environment.

Other ways to address the issue may exist, depending on the underlying cause, such as driver behavior, firmware quirks, scan scheduling, or NetworkManager configuration. The repository does not attempt to evaluate every possible solution.

Instead, it offers a small utility that automates a workaround that was simple, reliable, and sufficient to resolve the issue in the author's environment without requiring deeper system changes.

> This is a workaround for a specific class of Wi-Fi discovery issues. It does **not** fix:
> - driver crashes
> - firmware bugs
> - authentication failures
> - association issues
> - DHCP problems
> - general NetworkManager misconfiguration
>
> The utility intentionally relies on `iw` because the issue being worked around is specifically a case where a lower-level manual scan makes networks appear.

---

## Requirements

This project targets Linux systems using:

- NetworkManager (with `nmcli`)
- `systemd --user`
- `sudo`
- `iw`

The installer also expects common tools such as:

- `id`
- `getent`
- `cut`
- `install`
- `sed`
- `awk`
- `grep`
- `mktemp`
- `visudo`
- `rm`

If `SKIP_SYSTEMD=1` is **not** used, `systemctl` must also be available.

The verifier additionally uses common base-system tools such as `bash`, `cmp`, `stat`, `readlink`, and `dirname`.

---

## Compatibility

### Tested environment

Validated on CachyOS Linux with:

- Linux 7.1.x
- systemd 261
- NetworkManager 1.58
- wpa_supplicant 2.11
- `iw` 6.17
- Intel Dual Band Wireless-AC 3165 using `iwlwifi`

Other environments may also work if they meet the compatibility requirements below.

### Likely compatible environments

This project is most likely to work if all of the following are true:

- your Wi-Fi interface is managed by `NetworkManager`
- `iw dev <interface> scan` works on the target interface
- `systemd --user` is available for the target user session
- manual `iw` scanning already improves network discovery
- `nmcli radio wifi` correctly reflects Wi-Fi state changes
- the issue happens specifically during Wi-Fi enable/reenable transitions

### Likely incompatible or unsupported environments

This project is not intended for systems where:

- Wi-Fi is not managed by `NetworkManager`
- the system uses an `iwd`-only setup without NetworkManager
- running `iw dev <interface> scan` does not refresh visible networks
- environments where the Wi-Fi issue is unrelated to scan refreshes
- the issue is caused primarily by firmware, regulatory, or driver-level failures
- no persistent user `systemd --user` session is available

---

## Quickstart

```bash
git clone https://github.com/Noggurix/wifi-scan-fix.git
cd wifi-scan-fix
./install.sh
./verify.sh
systemctl --user status wifi-scan-fix.service
```

---

## Installation

### 1. Run the installer

Run as your normal user, not as root:

```bash
./install.sh
```

The script will request `sudo` immediately.

### 2. What the installer does:

- resolves the target user
- validates required commands
- checks the repository files exist
- detects the Wi-Fi interface using `iw dev`
- substitutes placeholders in the templates
- installs the watcher under your user account
- installs the root helper under `/usr/local/bin`
- installs the sudoers rule under `/etc/sudoers.d`
- validates the sudoers syntax with `visudo`
- installs the user `systemd` service
- reloads `systemd --user`
- enables and starts the service

### Install examples

#### Install with a specific Wi-Fi interface

```bash
WIFI_INTERFACE=wlp2s0 ./install.sh
```

#### Install in a test environment without a real Wi-Fi interface

```bash
ALLOW_MISSING_WIFI_INTERFACE=1 SKIP_SYSTEMD=1 ./install.sh
```

#### Install for a specific user in a test environment

```bash
TARGET_USER=testuser ALLOW_MISSING_WIFI_INTERFACE=1 SKIP_SYSTEMD=1 ./install.sh
```

---

## Verification

### Run the verifier:

```bash
./verify.sh
```

### Typical test/container usage

```bash
TARGET_USER=<user> SKIP_SYSTEMD=1 ./verify.sh
```

### What the verifier checks:

- installed watcher, helper, service, and sudoers rule
- systemd enable symlink presence and target when systemd checks are enabled
- ownership and permissions of installed files
- Bash syntax of the watcher and helper
- sudoers syntax
- unresolved installation placeholders
- interface consistency between the watcher and helper
- installed contents against the rendered repository templates
- passwordless sudo authorization for the restricted helper
- service enabled and running state
- loaded systemd service path
- pending `daemon-reload` state

### Useful commands

| Command | Description |
|---|---|
| `systemctl --user status wifi-scan-fix.service` | Check service status |
| `systemctl --user is-active wifi-scan-fix.service` | Check if the service is active |
| `systemctl --user is-enabled wifi-scan-fix.service` | Check if the service is enabled |
| `journalctl --user -u wifi-scan-fix.service -b` | View logs for the service |
| `journalctl --user -u wifi-scan-fix.service -f` | Follow logs in real time |

---

## Uninstallation

### 1. Run the uninstaller:

```bash
./uninstall.sh
```

The uninstaller removes everything that was installed by this project.

### 2. What the uninstaller does:

- stops and disables the user service
- removes the installed service file
- removes the watcher script
- removes the root helper
- removes the sudoers rule
- reloads the user `systemd` instance

---

## Configuration

### Supported environment variables:

#### `WIFI_INTERFACE`

Force a specific Wi-Fi interface during installation.

Example:

```bash
WIFI_INTERFACE=wlp2s0 ./install.sh
```

Use this when automatic interface detection is incorrect or when you explicitly want to target a known interface.

#### `TARGET_USER`

Override the user the scripts should operate on.

Example:

```bash
TARGET_USER=myuser ./install.sh
```

This is mostly useful for testing or controlled environments.

#### `SKIP_SYSTEMD`

Skip all `systemd --user` validation and activation logic.

Example:

```bash
SKIP_SYSTEMD=1 ./install.sh
```

This is mainly intended for containers or test environments where a real user session is not available.

When this is used:

- the installer still installs files
- the service is not reloaded
- the service is not enabled or started

#### `ALLOW_MISSING_WIFI_INTERFACE`

Allow installation to continue even if no real Wi-Fi interface is detected.

Example:

```bash
ALLOW_MISSING_WIFI_INTERFACE=1 ./install.sh
```

This is useful for:

- containers
- CI
- non-Wi-Fi test environments
- installer validation

When enabled, the installer uses a placeholder interface name (`wlan0`) for template substitution.

---

## How it works

### Project behavior after installation

Once installed, the watcher runs as a user service.

Its job is to:

- poll the Wi-Fi radio state via `nmcli`
- validate that the reported state is `enabled` or `disabled`
- detect when a scan is needed after Wi-Fi is enabled, at startup, or after state-query recovery
- call the restricted helper to perform the scan

The helper runs with restricted elevated permissions and performs the scan.

If a scan fails, the watcher makes up to three attempts, waiting two seconds between attempts. After three failures, it remains active and waits until a future event requires another scan instead of retrying indefinitely.

Temporary `nmcli` failures do not terminate the watcher. Repeated query failures produce one warning, followed by one recovery message when state detection works again.

The service uses `Restart=on-failure`, so systemd restarts it only if the watcher exits unexpectedly.

### Why `systemd --user`

This project uses `systemd --user` because:

- the service belongs to the user session
- there is no need for a full root daemon
- journald integration is easier
- the privilege surface stays smaller

### Security model

This project uses a minimal privilege design:

- the watcher runs as the normal user
- only the helper runs with elevated privileges
- the sudoers rule grants access only to the helper
- no unrestricted passwordless sudo is required

**Installed sudoers rule target:**

```text
/etc/sudoers.d/wifi-scan-fix
```

**Granted command:**

```text
/usr/local/bin/wifi-scan-fix-helper
```

This is intentionally narrower and safer than running the entire watcher as root.

### Logging

This project does **not** write to a custom log file.

Logs are collected by `systemd` and can be viewed with:

```bash
journalctl --user -u wifi-scan-fix.service
```

The watcher logs events rather than every polling cycle. During normal operation, the journal remains quiet until a meaningful event occurs.

Typical successful startup:

```text
watcher started interface=wlan0
Wi-Fi enabled; triggering scan interface=wlan0
scan completed interface=wlan0 attempt=1
```

Temporary query failure and recovery:

```text
failed to query Wi-Fi state
Wi-Fi state query recovered state=enabled
```

Transient scan failure:

```text
scan failed interface=wlan0 exit=42 attempt=1/3; retrying
scan completed interface=wlan0 attempt=2
```

After three failed attempts, the watcher stops retrying until another event requires a scan.

This is preferred over writing to `/tmp`, because:

- no log file grows indefinitely
- logging integrates with the system journal
- debugging is simpler
- service logs stay attached to the service itself

---

## Installed files

### User-level files:

#### `wifi-scan-fix-watcher`

The user-level watcher script template.

This is installed to:

```text
~/.local/bin/wifi-scan-fix-watcher
```

It monitors Wi-Fi radio state using `nmcli`, handles temporary query failures, and triggers the privileged helper when a scan is required.

#### `wifi-scan-fix.service`

The `systemd --user` service template.

This is installed to:

```text
~/.config/systemd/user/wifi-scan-fix.service
```

It runs the watcher automatically in the user's session and restarts it if it exits unexpectedly.

#### `service enable symlink`

This symlink is created at:

```text
~/.config/systemd/user/default.target.wants/wifi-scan-fix.service
```

It is created when the service is enabled and makes the user service start automatically with the user's `systemd --user` session.

### Root-level files:

#### `wifi-scan-fix-helper`

The root-only helper script template.

This is installed to:

```text
/usr/local/bin/wifi-scan-fix-helper
```

It runs the actual privileged command `iw dev <interface> scan`.

This helper is intentionally separated from the watcher so the watcher does not need broad root access.


#### `wifi-scan-fix.sudoers`

The sudoers template file.

This is installed to:

```text
/etc/sudoers.d/wifi-scan-fix
```

It grants permission for the current user to execute only this helper without a password:

```text
/usr/local/bin/wifi-scan-fix-helper
```

This keeps the privilege scope intentionally narrow.

---

## Troubleshooting

### The service is installed but not running

Check:

```bash
systemctl --user status wifi-scan-fix.service
journalctl --user -u wifi-scan-fix.service -b
```

### The installer says no Wi-Fi interface was detected

Try:

```bash
iw dev
```

Then install with:

```bash
WIFI_INTERFACE=<your-interface> ./install.sh
```

### The installer works in a container but verification cannot use systemd

That is expected if you used:

```bash
SKIP_SYSTEMD=1
```

In that mode, installation files can still be validated, but the service is not started.

### The sudoers rule seems broken

Check:

```bash
sudo visudo -cf /etc/sudoers.d/wifi-scan-fix
```

---

## Testing

The watcher includes a regression test suite that uses temporary mock commands. It does not disable the real Wi-Fi radio, invoke the installed helper, or require root privileges.

Run:

```bash
./tests/test-watcher.sh
```

The suite checks:

- Wi-Fi state query failure and recovery
- invalid `nmcli` output handling
- a single warning for repeated query failures
- a preventive scan after state query recovery
- recovery from a transient helper failure
- preservation of the helper exit status
- successful retry behavior
- the limit of three scan attempts
- continued watcher operation after persistent failures

The test suite requires common tools including Bash, `grep`, `sed`, `mktemp`, and `timeout`.

---

## License

- This project is licensed under the MIT License - see [LICENSE](./LICENSE) for details.
