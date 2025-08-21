# X‑Linuxtools

A Bash‑based toolkit for common Linux administration tasks. It supports both an interactive terminal menu and direct, non‑interactive command‑line invocation.

## Features

* Cross‑distribution support (`apt`, `dnf`/`yum`, `pacman`, `zypper`).
* Confirmation prompts before operations that change system state.

---

**Main entry point**

* `X-Linuxtools.sh` — command‑line utility and interactive menu.

**Helper scripts**

* `Scripts/Debian-Post-Installer.sh` — Debian desktop bootstrap (KDE, Flatpak, common tools).
* `Scripts/Virtualization_Setup.sh` — QEMU/KVM, libvirt, virt‑manager; default NAT network; group membership.
* `Scripts/Server-Updater.sh` — cross‑distro update routine with a cron schedule and logging.
* `Scripts/Docker-Install.sh` — Docker Engine from the official repositories; service enablement and basic verification.

---

## Usage

```bash
# Make executable and start the interactive menu
chmod +x X-Linuxtools.sh
./X-Linuxtools.sh

# List available actions
./X-Linuxtools.sh --list

# Run a specific action non‑interactively
./X-Linuxtools.sh <action>
```

### Available actions

* `sysinfo` — display basic system information (host, user, kernel, uptime, CPU, memory, and disk summaries).
* `update` — update system packages using the detected package manager (confirmation required).
* `cleanup` — clean package caches and old logs where supported; optional systemd‑journal vacuum.
* `debian_desktop_setup` — convert a fresh Debian CLI install into a KDE desktop (includes Flatpak/Discover, common tools). Reboots at the end.
* `yt_downloader` — launch a local YouTube downloader helper (uses `yt-dlp` and `ffmpeg`; fetches the Python helper if needed).
* `virtualization_setup` — install and configure KVM/QEMU, libvirt, and virt‑manager; enable the default NAT network and add the invoking user to the appropriate groups.
* `server_updater` — install a universal update routine and schedule it with cron (with logging and optional `--dry-run`).
* `docker_install` — install Docker Engine from the official repositories, enable and start the service, add the user to the `docker` group, and run a basic verification.

---

### One‑link runner (work in progress)

A single command to run X‑Linuxtools directly is in progress not sure when it will be final prime to use ass:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/main/X-Linuxtools.sh)
```

Until this is finalised, clone or download the repository and run the script locally.

## Supported distributions

The toolkit autodetects the available package manager and supports:

* `apt` (Debian/Ubuntu and derivatives)
* `dnf` / `yum` (Fedora/RHEL/Alma/Rocky/CentOS Stream/Oracle Linux)
* `pacman` (Arch/Manjaro/EndeavourOS, etc.)
* `zypper` (openSUSE)

Some actions require `sudo` privileges and an active internet connection, but would recommend running the script as root or sudo.

---

## Notes on specific actions

* **Debian desktop setup** installs KDE Plasma and common utilities, adjusts system settings, and reboots to complete installation.
* **Virtualization setup** enables and starts `libvirtd`, configures the default NAT network (`virbr0`), and adds the invoking user to the `libvirt`/`kvm` groups. Log out/in if group changes do not take effect immediately.
* **Server updater** deploys a small, distro‑aware update routine, installs a wrapper command, prompts for a schedule (cron), and logs to `/var/log/os_update.log`.
* **Docker install** configures the official Docker repository, installs `docker-ce`, `docker-ce-cli`, and `containerd.io` (plus plugins where applicable), enables/starts the service, and verifies the installation.

---

## License

This project is licensed under the MIT License. See [LICENSE](./LICENSE) for details.
