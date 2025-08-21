# X27 — Tiny Linux Toolbox (X‑Linuxtools)

A small, batteries‑included Bash toolbox for common Linux chores. Use it interactively via a clean menu or call actions directly from the CLI.

> **Highlights**
>
> * Cross‑distro: works with `apt`, `dnf`, and `pacman`
> * Safe by default: prompts before doing anything destructive
> * Ephemeral logs per run in `~/.local/share/x27/logs`
> * Color output (respects `NO_COLOR`)

---

## Contents / What it does

X27 ships one main script and a few helper scripts:

**Main entry point**

* `X-Linuxtools.sh` — the CLI & menu app (aka **X27**)

**Helper scripts** (called by actions below)

* `Scripts/Debian-Post-Installer.sh` — opinionated Debian desktop bootstrap (CLI → KDE, Flatpak, etc.)
* `Scripts/Virtualization_Setup.sh` — QEMU/KVM + libvirt + virt‑manager on apt/dnf/pacman
* `Scripts/Server-Updater.sh` — installs a cross‑distro updater and schedules it with cron
* `Scripts/Docker-Install.sh` — installs Docker Engine using the official repos and enables the service

### Built‑in actions

Run with **no args** to get a menu, or call an action directly:

```
./X-Linuxtools.sh <action>
```

Actions available:

* `sysinfo` – Show basic system information (CPU, memory, disk, kernel, uptime, distro).
* `update` – Update system packages (uses your distro’s package manager; asks for confirmation).
* `cleanup` – Safely clean caches/logs; asks for confirmation.
* `debian_desktop_setup` – Debian CLI → KDE setup (installs `kde-standard`, Flatpak + Discover backend, `fish`, `fastfetch`, `vlc`, and more). **Reboots at the end.**
* `yt_downloader` – Run a YouTube downloader (uses a local script if available; skips install if `yt-dlp` is already present).
* `virtualization_setup` – Install & enable KVM/QEMU, libvirt, virt‑manager; set up the default NAT network; add the invoking user to `libvirt`/`kvm` groups.
* `server_updater` – Deploy a universal update routine with a scheduled cron job. Creates `/usr/local/sbin/os_update.sh` plus `/usr/local/bin/update-system`, prompts for a day/time schedule, and logs to `/var/log/os_update.log`. Supports `--dry-run`.
* `docker_install` – Install Docker Engine from the official repos (Debian/RHEL‑like), enable & start the `docker` service, add the invoking user to the `docker` group, and run the `hello-world` test.

> Tip: Get a quick list any time with `./X-Linuxtools.sh --list`.

---

## Quick start

```bash
# Make it executable and run
chmod +x X-Linuxtools.sh
./X-Linuxtools.sh         # interactive menu
./X-Linuxtools.sh update  # run a specific action
```

### One‑link command (WIP)

A single **one‑link** command to run X27 directly from GitHub is being prepared. The planned UX will be something like:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/main/X-Linuxtools.sh)
```

> Until that’s finalized, clone or download the repo and run the script locally. As always, review scripts before piping from the internet.

---

## CLI flags & environment

```
./X-Linuxtools.sh --help      # usage
./X-Linuxtools.sh --version   # print version
./X-Linuxtools.sh --list      # list actions
./X-Linuxtools.sh --dry-run   # preview commands without making changes
```

Environment variables:

* `X27_LOG_DIR` – custom log directory (default: `~/.local/share/x27/logs`)
* `X27_CONF_DIR` – config directory (default: `~/.config/x27`)
* `X27_DRY_RUN`  – set to `true` to force dry‑run
* `NO_COLOR`     – disable colored output if set

---

## Distro support

X27 autodetects the package manager and supports:

* `apt` (Debian/Ubuntu and derivatives)
* `dnf` (Fedora/RHEL/Alma/Rocky/CentOS Stream/Oracle Linux)
* `pacman` (Arch/Manjaro/EndeavourOS, etc.)

Some actions require `sudo` and an active internet connection to fetch dependencies or helper scripts.

---

## Notes on specific actions

* **Debian desktop setup** is intentionally opinionated and designed for fresh CLI installs. It installs KDE Plasma and common tools, adjusts a few system bits, and **reboots automatically** at the end.
* **Virtualization setup** enables `libvirtd`, configures the default NAT network (`virbr0`), and adds your user to `libvirt`/`kvm`. Log out/in if group changes don’t take effect right away.
* **Server updater** writes a small, distro‑aware update routine, installs a wrapper command, and asks when to run it via cron. Logs go to `/var/log/os_update.log`.
* **Docker install** configures the official Docker repository, installs `docker-ce`, `docker-ce-cli`, and `containerd.io`, starts/enables the service, and runs `hello-world` to verify.

---

## Contributing

Issues and PRs are welcome! If you’re proposing a new action, try to:

1. Keep it cross‑distro (or clearly gate by distro).
2. Prompt before destructive changes and offer `--dry-run`.
3. Log meaningful steps and exit with helpful errors.

---

## License

[MIT](./LICENSE) © 2025 X27
