#!/usr/bin/env bash
# X27 — sysinfo, update, cleanup, debian_desktop_setup, yt_downloader, virtualization_setup, server_updater, docker_install
# Clean banner menu • logs deleted after each run

set -Eeuo pipefail

APP_NAME="X27"
APP_CMD="${0##*/}"
VERSION="0.6.8"

LOG_DIR="${X27_LOG_DIR:-$HOME/.local/share/x27/logs}"
CONF_DIR="${X27_CONF_DIR:-$HOME/.config/x27}"
DRY_RUN="${X27_DRY_RUN:-false}"
NO_COLOR="${NO_COLOR:-}"

# --- URLs for external scripts ---
DEBIAN_POST_URL="https://raw.githubusercontent.com/GamerX27/X-Linuxtools/refs/heads/main/Scripts/Debian-Post-Installer.sh"
DEBIAN_POST_LOCAL_NAME="Debian-Post-Installer.sh"
DEBIAN_POST_LOCAL_FALLBACK="/Scripts/Debian-Post-Installer.sh"

YTDL_PY_URL="https://raw.githubusercontent.com/GamerX27/YT-Downloader-Script/refs/heads/main/YT-Downloader-Cli.py"

VIRT_LOCAL_FALLBACK="/Scripts/Virtualization_Setup.sh"
VIRT_LOCAL_NAME="Virtualization_Setup.sh"
VIRT_URL="https://raw.githubusercontent.com/GamerX27/X-Linuxtools/refs/heads/main/Scripts/Virtualization_Setup.sh"

SERVER_UPDATER_URL="https://raw.githubusercontent.com/GamerX27/X-Linuxtools/refs/heads/main/Scripts/Server-Updater.sh"
SERVER_UPDATER_LOCAL_NAME="Server-Updater.sh"

DOCKER_INSTALL_URL="https://raw.githubusercontent.com/GamerX27/X-Linuxtools/refs/heads/main/Scripts/Docker-Install.sh"
DOCKER_INSTALL_LOCAL_NAME="Docker-Install.sh"

# --- Safe clear (works in minimal shells) ---
safe_clear() {
  if command -v clear >/dev/null 2>&1; then clear; else printf "\n%.0s" {1..5}; fi
}

# --- Colors (respects NO_COLOR) ---
if [[ -z "${NO_COLOR}" ]]; then
  BOLD=$'\e[1m'; DIM=$'\e[2m'; RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; CYA=$'\e[36m'; RST=$'\e[0m'
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; CYA=""; RST=""
fi

mkdir -p "$LOG_DIR" "$CONF_DIR"
LOG_FILE="$LOG_DIR/$(date +%F_%H-%M-%S).log"

# --- Logging helpers ---
msg()  { printf "%s\n" "$*"; }
inf()  { printf "%sℹ%s %s\n" "$CYA" "$RST" "$*"; }
ok()   { printf "%s✔%s %s\n" "$GRN" "$RST" "$*"; }
warn() { printf "%s!%s %s\n"  "$YLW" "$RST" "$*"; }
err()  { printf "%s✖%s %s\n" "$RED" "$RST" "$*" >&2; }
log()  { printf "[%(%F %T)T] %s\n" -1 "$*" >>"$LOG_FILE"; }

confirm() {
  local prompt="${1:-Are you sure?}" ans
  read -r -p "$prompt [y/N] " ans || true
  [[ "${ans,,}" == y || "${ans,,}" == yes ]]
}

# --- Privilege helper ---
sudo_maybe() {
  if [[ $EUID -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then sudo "$@"; else err "This action requires root and 'sudo' is not installed."; return 1; fi
  else "$@"; fi
}

run() {
  log "RUN: $*"
  if [[ "$DRY_RUN" == true ]]; then warn "[dry-run] $*"; else "$@"; fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# --- Package manager detection ---
detect_pkg() {
  if   have apt-get; then echo apt
  elif have dnf;     then echo dnf
  elif have yum;     then echo yum
  elif have pacman;  then echo pacman
  elif have zypper;  then echo zypper
  else echo unknown; return 1; fi
}

# --- Base dependency check & install (wget, curl, git, sudo) ---
install_with_mgr() {
  local mgr="$1"; shift
  local pkgs=("$@")
  case "$mgr" in
    apt)
      if have apt-get; then
        run ${USE_SUDO:-} apt-get update
        run ${USE_SUDO:-} apt-get -y install "${pkgs[@]}"
      fi;;
    dnf)    run ${USE_SUDO:-} dnf -y install "${pkgs[@]}" ;;
    yum)    run ${USE_SUDO:-} yum -y install "${pkgs[@]}" ;;
    pacman) run ${USE_SUDO:-} pacman -Sy --noconfirm "${pkgs[@]}" ;;
    zypper) run ${USE_SUDO:-} zypper --non-interactive in "${pkgs[@]}" ;;
    *)      return 1 ;;
  esac
}

base_deps_check_install() {
  local deps=(wget curl git sudo) missing=() mgr use_sudo_cmd=""
  for d in "${deps[@]}"; do have "$d" || missing+=("$d"); done
  if [[ ${#missing[@]} -eq 0 ]]; then ok "Base deps present: wget curl git sudo"; return 0; fi

  mgr=$(detect_pkg) || { err "Unsupported package manager. Please install: ${missing[*]}"; return 1; }

  # Decide whether to prefix with sudo
  if [[ $EUID -ne 0 ]]; then
    if have sudo; then USE_SUDO="sudo"; else
      # sudo is missing and we're not root
      err "'sudo' is missing and you are not root. Re-run as root (e.g., 'su -' then run script) or install sudo manually."; return 1
    fi
  else
    USE_SUDO=""
  fi

  inf "Installing missing base deps via $mgr: ${missing[*]}"
  install_with_mgr "$mgr" "${missing[@]}" || { err "Failed to install: ${missing[*]}"; return 1; }
  ok "Base dependencies installed."
}

# =================== Dependency installers used by features ===================
ensure_wget() { have wget && return 0; warn "wget not found. Installing…"; base_deps_check_install; }
ensure_python3() {
  if have python3; then return 0; fi; warn "python3 not found. Installing…"; local mgr; mgr=$(detect_pkg) || { err unknown pkg mgr; return 1; }
  [[ $EUID -ne 0 && ! $(have sudo && echo yes) ]] && { err "Need root/sudo to install python3"; return 1; }
  case "$mgr" in
    apt)    run ${USE_SUDO:-sudo} apt-get update; run ${USE_SUDO:-sudo} apt-get -y install python3 ;;
    dnf)    run ${USE_SUDO:-sudo} dnf -y install python3 ;;
    yum)    run ${USE_SUDO:-sudo} yum -y install python3 ;;
    pacman) run ${USE_SUDO:-sudo} pacman -Sy --noconfirm python ;;
    zypper) run ${USE_SUDO:-sudo} zypper --non-interactive in python3 ;;
    *)      err "Unknown package manager"; return 1 ;;
  esac
}
ensure_pip3() {
  have pip3 && return 0; warn "pip3 not found. Installing…"; local mgr; mgr=$(detect_pkg) || { err unknown pkg mgr; return 1; }
  case "$mgr" in
    apt)    run ${USE_SUDO:-sudo} apt-get -y install python3-pip ;;
    dnf)    run ${USE_SUDO:-sudo} dnf -y install python3-pip ;;
    yum)    run ${USE_SUDO:-sudo} yum -y install python3-pip ;;
    pacman) run ${USE_SUDO:-sudo} pacman -Sy --noconfirm python-pip ;;
    zypper) run ${USE_SUDO:-sudo} zypper --non-interactive in python3-pip ;;
    *)      err "Unknown package manager"; return 1 ;;
  esac
}
ensure_ffmpeg() {
  have ffmpeg && return 0; warn "ffmpeg not found. Installing…"; local mgr; mgr=$(detect_pkg) || { err unknown pkg mgr; return 1; }
  case "$mgr" in
    apt)    run ${USE_SUDO:-sudo} apt-get -y install ffmpeg ;;
    dnf)    run ${USE_SUDO:-sudo} dnf -y install ffmpeg ;;
    yum)    run ${USE_SUDO:-sudo} yum -y install ffmpeg || true ;;
    pacman) run ${USE_SUDO:-sudo} pacman -Sy --noconfirm ffmpeg ;;
    zypper) run ${USE_SUDO:-sudo} zypper --non-interactive in ffmpeg ;;
    *)      err "Unknown package manager"; return 1 ;;
  esac
}
ensure_ytdlp() {
  have yt-dlp && return 0
  warn "yt-dlp not found. Attempting distro install…"
  local mgr ok=false; mgr=$(detect_pkg) || true
  case "$mgr" in
    apt)    run ${USE_SUDO:-sudo} apt-get -y install yt-dlp && ok=true ;;
    dnf)    run ${USE_SUDO:-sudo} dnf -y install yt-dlp && ok=true ;;
    yum)    run ${USE_SUDO:-sudo} yum -y install yt-dlp && ok=true || true ;;
    pacman) run ${USE_SUDO:-sudo} pacman -Sy --noconfirm yt-dlp && ok=true ;;
    zypper) run ${USE_SUDO:-sudo} zypper --non-interactive in yt-dlp && ok=true || true ;;
  esac
  if [[ $ok != true ]]; then
    warn "Falling back to pip (user)."
    ensure_pip3 || return 1
    run pip3 install --user -U yt-dlp
    [[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"
    have yt-dlp || { err "yt-dlp still not found; add ~/.local/bin to PATH"; return 1; }
  fi
}
ensure_yt_deps() { ensure_wget && ensure_python3 && ensure_ffmpeg && ensure_ytdlp; }

# ================================ Actions ====================================
x27_sysinfo() {
  inf "Host: $(hostname)"; inf "User: $USER"; inf "Kernel: $(uname -srmo 2>/dev/null || uname -sr)"; inf "Uptime: $(uptime -p || true)"
  if source /etc/os-release 2>/dev/null; then inf "Distro: ${NAME:-Unknown} ${VERSION:-}"; else inf "Distro: Unknown"; fi
  echo; inf "CPU:"; lscpu 2>/dev/null | sed -n '1,8p' || true
  echo; inf "Memory:"; free -h || true
  echo; inf "Disk:"; df -hT --total | sed -n '1,10p' || true
}

x27_update() {
  local mgr; mgr=$(detect_pkg) || { err "No supported package manager."; return 1; }
  warn "This will update system packages using: $mgr"
  confirm "Proceed with system update?" || { warn "Canceled."; return 0; }
  case "$mgr" in
    apt)    run ${USE_SUDO:-sudo} apt-get update; run ${USE_SUDO:-sudo} apt-get -y upgrade; run ${USE_SUDO:-sudo} apt-get -y autoremove ;;
    dnf)    run ${USE_SUDO:-sudo} dnf -y upgrade ;;
    yum)    run ${USE_SUDO:-sudo} yum -y update ;;
    pacman) run ${USE_SUDO:-sudo} pacman -Syu --noconfirm ;;
    zypper) run ${USE_SUDO:-sudo} zypper refresh; run ${USE_SUDO:-sudo} zypper update -y ;;
    *)      err "Unsupported package manager: $mgr"; return 1 ;;
  esac
  ok "System update complete."
}

x27_cleanup() {
  inf "Cleaning package caches and old logs where possible."
  confirm "Proceed with cleanup?" || { warn "Canceled."; return 0; }
  local mgr; mgr=$(detect_pkg) || true
  case "$mgr" in
    apt)     run ${USE_SUDO:-sudo} apt-get -y autoremove; run ${USE_SUDO:-sudo} apt-get -y autoclean ;;
    dnf|yum) run ${USE_SUDO:-sudo} "$mgr" clean all -y ;;
    pacman)  run ${USE_SUDO:-sudo} paccache -r -k2 2>/dev/null || true ;;
    zypper)  run ${USE_SUDO:-sudo} zypper clean -a ;;
  esac
  if have journalctl && confirm "Vacuum systemd journal to 200M?"; then run ${USE_SUDO:-sudo} journalctl --vacuum-size=200M; fi
  ok "Cleanup done."
}

x27_debian_desktop_setup() {
  echo; inf "Debian Desktop Setup (CLI → KDE)"; msg " - KDE Standard, Flatpak+Discover, fish/fastfetch/VLC, Flathub, cleanup, reboot"
  warn "Debian-focused. This will make desktop changes and trigger a reboot."
  confirm "Run the Debian Desktop Setup now?" || { warn "Canceled."; return 0; }
  local runner=""
  if [[ -f "$DEBIAN_POST_LOCAL_FALLBACK" ]]; then inf "Found local: $DEBIAN_POST_LOCAL_FALLBACK"; runner="$DEBIAN_POST_LOCAL_FALLBACK"
  else ensure_wget || return 1; inf "Downloading → ./$DEBIAN_POST_LOCAL_NAME"; run bash -c "wget -qO '$DEBIAN_POST_LOCAL_NAME' '$DEBIAN_POST_URL'"; run chmod +x "$DEBIAN_POST_LOCAL_NAME"; runner="./$DEBIAN_POST_LOCAL_NAME"; fi
  inf "Executing: $runner"; run sudo_maybe bash "$runner"; ok "Debian Desktop Setup complete (system may reboot)."
}

x27_yt_downloader() {
  echo; inf "YT Downloader (local script)"; msg " - yt-dlp + ffmpeg; downloads to ./YT-Downloads"
  local fname="YT-Downloader-Cli.py"
  if have yt-dlp; then
    ok "yt-dlp detected"; have python3 || { err "python3 missing"; return 1; }
    [[ -f "$fname" ]] || { have wget || { err "wget missing"; return 1; }; inf "Fetching → ./$fname"; run bash -c "wget -qO '$fname' '$YTDL_PY_URL'"; }
    inf "Launching: python3 $fname"; run python3 "$fname" || true; ok "Done. Files → ./YT-Downloads"; return 0
  fi
  warn "yt-dlp not found. Installing prerequisites…"; ensure_yt_deps || return 1
  [[ -f "$fname" ]] || { inf "Fetching → ./$fname"; run bash -c "wget -qO '$fname' '$YTDL_PY_URL'"; }
  inf "Launching: python3 $fname"; run python3 "$fname" || true; ok "Done. Files → ./YT-Downloads"
}

x27_virtualization_setup() {
  echo; inf "Virtualization Setup (KVM/QEMU + virt-manager)"; msg " - Installs QEMU/KVM, libvirt, virt-manager; enables libvirtd; NAT; group access"
  confirm "Proceed with Virtualization Setup?" || { warn "Canceled."; return 0; }
  local runner=""
  if [[ -f "$VIRT_LOCAL_FALLBACK" ]]; then inf "Found local: $VIRT_LOCAL_FALLBACK"; runner="$VIRT_LOCAL_FALLBACK"
  else ensure_wget || return 1; inf "Downloading → ./$VIRT_LOCAL_NAME"; run bash -c "wget -qO '$VIRT_LOCAL_NAME' '$VIRT_URL'"; run chmod +x "$VIRT_LOCAL_NAME"; runner="./$VIRT_LOCAL_NAME"; fi
  inf "Executing: $runner"; run sudo_maybe bash "$runner"; ok "Virtualization ready. Try: virt-manager"
}

x27_server_updater() {
  echo; inf "Deploy Server Updater"; msg " - Universal updater (update-system) + cron (optional auto-reboot)"
  confirm "Proceed with Server Updater setup?" || { warn "Canceled."; return 0; }
  ensure_wget || return 1
  inf "Downloading → ./$SERVER_UPDATER_LOCAL_NAME"; run bash -c "wget -qO '$SERVER_UPDATER_LOCAL_NAME' '$SERVER_UPDATER_URL'"; run chmod +x "$SERVER_UPDATER_LOCAL_NAME"
  inf "Executing: sudo bash $SERVER_UPDATER_LOCAL_NAME"; run sudo_maybe bash "$SERVER_UPDATER_LOCAL_NAME"; ok "Server Updater deployed."
}

x27_docker_install() {
  echo; inf "Docker Install"; msg " - Detects Debian/RHEL; installs Docker Engine + plugins; adds user to docker group; optional Portainer"
  confirm "Proceed with Docker Install?" || { warn "Canceled."; return 0; }
  ensure_wget || return 1
  inf "Downloading → ./$DOCKER_INSTALL_LOCAL_NAME"; run bash -c "wget -qO '$DOCKER_INSTALL_LOCAL_NAME' '$DOCKER_INSTALL_URL'"; run chmod +x "$DOCKER_INSTALL_LOCAL_NAME"
  inf "Executing: sudo bash $DOCKER_INSTALL_LOCAL_NAME"; run sudo_maybe bash "$DOCKER_INSTALL_LOCAL_NAME"; ok "Docker install routine finished (log out/in may be required for group changes)."
}

# ============================ Registration ===================================
declare -a ACTIONS=(
  "sysinfo" "update" "cleanup" "debian_desktop_setup" "yt_downloader" "virtualization_setup" "server_updater" "docker_install"
)

declare -a DESCRIPTIONS=(
  "Show basic system information (CPU/mem/disk)."
  "Update system packages (asks for confirmation)."
  "Clean caches/logs safely (asks for confirmation)."
  "Debian Desktop Setup (CLI→KDE)."
  "YT Downloader: Local script; skips install if yt-dlp is present."
  "Virtualization Setup: KVM/QEMU, libvirt, virt-manager; enable libvirtd; NAT."
  "Deploy Server Updater: Universal updater + cron (optional auto-reboot)."
  "Docker install: Engine+plugins, docker group, optional Portainer."
)

list_actions() { local i; for (( i=0; i<${#ACTIONS[@]}; i++ )); do printf "  %-22s %s\n" "${ACTIONS[$i]}" "${DESCRIPTIONS[$i]}"; done; }

run_action() {
  local name="$1"; shift || true
  case "$name" in
    sysinfo)              x27_sysinfo "$@";;
    update)               x27_update "$@";;
    cleanup)              x27_cleanup "$@";;
    debian_desktop_setup) x27_debian_desktop_setup "$@";;
    yt_downloader)        x27_yt_downloader "$@";;
    virtualization_setup) x27_virtualization_setup "$@";;
    server_updater)       x27_server_updater "$@";;
    docker_install)       x27_docker_install "$@";;
    *) err "Unknown action: $name"; exit 1;;
  esac
}

usage() {
  printf "%s%s%s v%s\n" "$BOLD" "$APP_NAME" "$RST" "$VERSION"
  echo "Minimal toolbox. Logs are deleted after each run."; echo
  echo "Usage:"; echo "  $APP_CMD                 # interactive menu"; echo "  $APP_CMD <action>        # run a specific tool"; echo "  $APP_CMD --help | --list | --version"; echo "  $APP_CMD --dry-run <action>"; echo
  echo "Actions:"; list_actions
}

# -------------------------------- Menu ---------------------------------------
menu() {
  safe_clear
  echo "${CYA}============================================${RST}"
  echo "${BOLD}${APP_NAME}${RST} ${DIM}- Your Linux Utility Toolbox${RST}"
  echo "${CYA}============================================${RST}"; echo
  local i; for (( i=0; i<${#ACTIONS[@]}; i++ )); do printf "%2d) %-22s %s\n" "$((i+1))" "${ACTIONS[$i]}" "${DESCRIPTIONS[$i]}"; done
  echo " q) quit"; echo
  while true; do
    read -rp "Select an option: " choice || exit 0
    case "$choice" in
      q|Q) exit 0 ;;
      '' ) continue ;;
      *  ) if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#ACTIONS[@]} )); then
              local action="${ACTIONS[$((choice-1))]}"; echo; inf "Running: $action"; run_action "$action"; echo
              read -rp "Press Enter to continue..." _ || true
              safe_clear; menu; return
            else warn "Invalid selection."; fi;;
    esac
  done
}

# Delete log on exit to keep the tool lightweight
cleanup_logs() { [[ -f "$LOG_FILE" ]] && rm -f "$LOG_FILE"; }
trap cleanup_logs EXIT

# -------------------------------- CLI ----------------------------------------
main() {
  # Pre-run: ensure base deps (wget, curl, git, sudo) exist and install if possible
  base_deps_check_install || exit 1

  # Process CLI
  if [[ $# -eq 0 ]]; then menu; exit 0; fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) usage; exit 0 ;;
      --version) echo "$APP_NAME $VERSION"; exit 0 ;;
      --list)    list_actions; exit 0 ;;
      --dry-run) DRY_RUN=true; shift; continue ;;
      -*)        err "Unknown option: $1"; usage; exit 1 ;;
      *)         run_action "$1" "${@:2}"; exit $? ;;
    esac
  done
}
main "$@"
