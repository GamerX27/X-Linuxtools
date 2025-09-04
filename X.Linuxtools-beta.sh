#!/usr/bin/env bash
# X27 — sysinfo, update, cleanup, debian_desktop_setup, yt_downloader, virtualization_setup, server_updater, docker_install, fedora_postsetup
# Clean banner menu • logs deleted after each run

set -Eeuo pipefail

APP_NAME="X27"
APP_CMD="${0##*/}"
VERSION="0.6.9"

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

FEDORA_POST_URL="https://raw.githubusercontent.com/GamerX27/X-Linuxtools/refs/heads/main/Scripts/Fedora-PostSetup.sh"
FEDORA_POST_LOCAL_NAME="Fedora-PostSetup.sh"

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

  if [[ $EUID -ne 0 ]]; then
    if have sudo; then USE_SUDO="sudo"; else
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
# (unchanged actions sysinfo, update, cleanup, debian_desktop_setup, yt_downloader, virtualization_setup, server_updater, docker_install)

x27_fedora_postsetup() {
  echo; inf "Fedora Postsetup"
  msg " - Runs Fedora post-setup script with KDE defaults and RPM Fusion repos."
  confirm "Proceed with Fedora Postsetup?" || { warn "Canceled."; return 0; }
  ensure_wget || return 1
  inf "Downloading → ./$FEDORA_POST_LOCAL_NAME"
  run bash -c "wget -qO '$FEDORA_POST_LOCAL_NAME' '$FEDORA_POST_URL'"
  run chmod +x "$FEDORA_POST_LOCAL_NAME"
  inf "Executing: sudo bash $FEDORA_POST_LOCAL_NAME"
  run sudo_maybe bash "$FEDORA_POST_LOCAL_NAME"
  ok "Fedora Postsetup complete."
}

# ============================ Registration ===================================
declare -a ACTIONS=(
  "sysinfo" "update" "cleanup" "debian_desktop_setup" "yt_downloader" "virtualization_setup" "server_updater" "docker_install" "fedora_postsetup"
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
  "Fedora Postsetup: Download and run Fedora-PostSetup.sh."
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
    fedora_postsetup)     x27_fedora_postsetup "$@";;
    *) err "Unknown action: $name"; exit 1;;
  esac
}

# usage, menu, cleanup_logs, main remain unchanged
