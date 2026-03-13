# wifi-scan-fix

![GitHub License](https://img.shields.io/github/license/Noggurix/wifi-scan-fix?style=flat-square&color=%2300060) ![Platform](https://img.shields.io/badge/platform-linux-blue) ![Shell](https://img.shields.io/badge/language-shell-green)

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
3. Runs a privileged scan helper once when Wi-Fi becomes enabled
4. Allows NetworkManager to see the refreshed scan results

This ensures that Wi-Fi networks become visible immediately after enabling the Wi-Fi radio, without requiring a manual scan.

This project provides a pragmatic solution by automating a workaround that proved reliable in the tested environment.

There may be other approaches to solving this issue depending on the underlying cause (driver behavior, firmware quirks, scan scheduling, or NetworkManager configuration). This repository does not attempt to evaluate every possible solution.

Instead, it provides a small utility that automates a workaround that was simple, reliable, and sufficient to resolve the issue in the author's environment without requiring deeper changes to the system.

> This is a workaround for a specific class of Wi-Fi discovery issues. It does **not** fix:
>	- driver crashes
>	- firmware bugs
>	- authentication failures
>	- association issues
>	- DHCP problems
>	- general NetworkManager misconfiguration
>
> This project intentionally relies on `iw` because the issue being worked around is specifically a case where a lower-level manual scan makes networks appear.

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

---

## Compatibility

### Tested environment

This project was validated in the following environment:

System:
- Architecture: x86_64
- Kernel: Linux 6.19.6-2-cachyos
- Distro: CachyOS (Arch-based)
- Init system: systemd 259 (259.3-1-arch)

Desktop session:
- DE: KDE Plasma 6.6.2
- WM: KWin (Wayland)

Networking stack:
- NetworkManager: 1.56.0-1
- Wi-Fi backend: wpa_supplicant
- wpa_supplicant: v2.11-hostap_2_11+
- Wi-Fi tools: `iw`, `sudo`
- iw version: 6.17

Wi-Fi hardware:
- Device: Intel Dual Band Wireless-AC 3165
- Kernel driver: `iwlwifi`
- Firmware: `7265D-29.ucode`
- Firmware version: `29.9ef079ed.0`
- Interface: `wlan0`

Wi-Fi workflow tested:
- Wi-Fi managed by NetworkManager
- Wi-Fi toggled via NetworkManager (desktop UI / `nmcli`)

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
- systems where running `iw dev <interface> scan` does not refresh visible networks
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

- watcher file presence
- service file presence
- enable symlink presence
- helper presence
- sudoers rule presence
- sudoers syntax
- service enabled/running state

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
- detect a transition from disabled to enabled
- call the helper once when Wi-Fi is enabled

The helper runs with restricted elevated permissions and performs the scan.

The service automatically restarts if it exits unexpectedly.

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

It monitors Wi-Fi radio state using `nmcli` and triggers the privileged helper when Wi-Fi becomes enabled.

#### `wifi-scan-fix.service`

The `systemd --user` service template.

This is installed to:

```text
~/.config/systemd/user/wifi-scan-fix.service
```

It runs the watcher automatically in the user's session and keeps it alive.

#### `service enable symlink`

This symlink is created at:

```text
~/.config/systemd/user/default.target.wants/wifi-scan-fix.service
```

It is created when the service is enabled and makes the user service start automatically with the user's `systemd --user` session

### Root-level files:

#### `wifi-scan-fix-helper`

The root-only helper script template.

This is installed to:

```text
/usr/local/bin/wifi-scan-fix-helper
```

It runs the actual privileged command `iw dev <interface> scan`

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

## License

- This project is licensed under the MIT License - see [LICENSE](./LICENSE) for details.