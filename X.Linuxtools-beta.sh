#!/usr/bin/env bash
# X27 — sysinfo, update, cleanup, debian_desktop_setup, yt_downloader,
#        virtualization_setup, server_updater, docker_install,
#        fedora_postsetup, brave_debloat, proton_cachyos_installer
# Clean banner menu • logs deleted after each run • logs in ./logs

# ---------------- Strict mode ----------------
set -Eeuo pipefail
IFS=$' \t\n'

# ---------------- Metadata ----------------
APP_NAME="X27"
APP_CMD="${0##*/}"
VERSION="0.10.0"

# ---------------- External script URLs ----------------
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

BRAVE_DEBLOAT_URL="https://raw.githubusercontent.com/GamerX27/X-Linuxtools/refs/heads/main/Scripts/make_brave_great_again.sh"
BRAVE_DEBLOAT_LOCAL_NAME="make_brave_great_again.sh"

# Gaming: Proton-CachyOS installer
PROTON_CACHY_URL="https://raw.githubusercontent.com/GamerX27/X-Linuxtools/refs/heads/main/Scripts/proton-cachyos-installer.sh"
PROTON_CACHY_LOCAL_NAME="proton-cachyos-installer.sh"

# ---------------- Colors ----------------
if [[ -t 1 ]]; then
  BOLD=$'\e[1m'; DIM=$'\e[2m'; RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; CYA=$'\e[36m'; RST=$'\e[0m'
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; CYA=""; RST=""
fi

# ---------------- Logging ----------------
LOG_DIR="./logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%F_%H-%M-%S).log"
trap '[[ -f "$LOG_FILE" ]] && rm -f "$LOG_FILE"' EXIT

timestamp() { date +'%F %T'; }
log()  { printf "[%s] %s\n" "$(timestamp)" "$*" >>"$LOG_FILE"; }
msg()  { printf "%s\n" "$*"; }
inf()  { printf "%sℹ%s %s\n" "$CYA" "$RST" "$*"; }
ok()   { printf "%s✔%s %s\n" "$GRN" "$RST" "$*"; }
warn() { printf "%s!%s %s\n"  "$YLW" "$RST" "$*"; }
err()  { printf "%s✖%s %s\n" "$RED" "$RST" "$*" >&2; }

safe_clear() { if command -v clear >/dev/null 2>&1 && [[ -t 1 ]]; then clear; else printf "\n%.0s" {1..5}; fi; }
have() { command -v "$1" >/dev/null 2>&1; }

sudo_maybe() {
  if [[ $EUID -ne 0 ]]; then
    if have sudo; then sudo "$@"; else err "This action requires root and 'sudo' is not installed."; return 1; fi
  else "$@"; fi
}

# Prompt for sudo once per action (when needed)
sudo_warmup() {
  if [[ $EUID -ne 0 ]] && have sudo; then
    sudo -v || { err "sudo authentication failed."; return 1; }
    ( while true; do sleep 60; sudo -n true 2>/dev/null || exit; done ) &
    export SUDO_KEEPA_PID=$!
    trap '[[ -n "${SUDO_KEEPA_PID:-}" ]] && kill "$SUDO_KEEPA_PID" 2>/dev/null || true' RETURN
  fi
}

run() { log "RUN: $*"; "$@"; }

confirm() {
  local prompt="${1:-Are you sure?}" ans
  read -r -p "$prompt [y/N] " ans || true
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

# ---------------- Base deps (invoked by actions only) ----------------
detect_pkg() {
  if   have apt-get; then echo apt
  elif have dnf;     then echo dnf
  elif have yum;     then echo yum
  elif have pacman;  then echo pacman
  elif have zypper;  then echo zypper
  else echo unknown; return 1; fi
}

install_with_mgr() {
  local mgr="$1"; shift
  case "$mgr" in
    apt)    run sudo_maybe apt-get update; run sudo_maybe apt-get -y install "$@" ;;
    dnf)    run sudo_maybe dnf -y install "$@" ;;
    yum)    run sudo_maybe yum -y install "$@" ;;
    pacman) run sudo_maybe pacman -Sy --noconfirm "$@" ;;
    zypper) run sudo_maybe zypper --non-interactive in "$@" ;;
    *)      return 1 ;;
  esac
}

base_deps_check_install() {
  local deps=(wget curl git) missing=() mgr
  for d in "${deps[@]}"; do have "$d" || missing+=("$d"); done
  if [[ ${#missing[@]} -eq 0 ]]; then ok "Base deps present: wget curl git"; return 0; fi
  mgr=$(detect_pkg) || { err "Unsupported package manager. Please install: ${missing[*]}"; return 1; }
  inf "Installing missing deps via $mgr: ${missing[*]}"
  sudo_warmup || true
  install_with_mgr "$mgr" "${missing[@]}" || { err "Failed to install: ${missing[*]}"; return 1; }
  ok "Base dependencies installed."
}

# ---------------- Dependency helpers ----------------
ensure_wget() { have wget && return 0 || { warn "wget not found. Installing…"; base_deps_check_install; }; }

ensure_python3() {
  have python3 && return 0
  warn "python3 not found. Installing…"
  local mgr; mgr=$(detect_pkg) || { err "Unknown package manager"; return 1; }
  sudo_warmup || true
  case "$mgr" in
    apt)    run sudo_maybe apt-get update; run sudo_maybe apt-get -y install python3 ;;
    dnf)    run sudo_maybe dnf -y install python3 ;;
    yum)    run sudo_maybe yum -y install python3 ;;
    pacman) run sudo_maybe pacman -Sy --noconfirm python ;;
    zypper) run sudo_maybe zypper --non-interactive in python3 ;;
    *)      err "Unknown package manager"; return 1 ;;
  esac
}

ensure_pip3() {
  have pip3 && return 0
  warn "pip3 not found. Installing…"
  local mgr; mgr=$(detect_pkg) || { err "Unknown package manager"; return 1; }
  sudo_warmup || true
  case "$mgr" in
    apt)    run sudo_maybe apt-get -y install python3-pip ;;
    dnf)    run sudo_maybe dnf -y install python3-pip ;;
    yum)    run sudo_maybe yum -y install python3-pip ;;
    pacman) run sudo_maybe pacman -Sy --noconfirm python-pip ;;
    zypper) run sudo_maybe zypper --non-interactive in python3-pip ;;
    *)      err "Unknown package manager"; return 1 ;;
  esac
}

ensure_ffmpeg() {
  have ffmpeg && return 0
  warn "ffmpeg not found. Installing…"
  local mgr; mgr=$(detect_pkg) || { err "Unknown package manager"; return 1; }
  sudo_warmup || true
  case "$mgr" in
    apt)    run sudo_maybe apt-get -y install ffmpeg ;;
    dnf)    run sudo_maybe dnf -y install ffmpeg ;;
    yum)    run sudo_maybe yum -y install ffmpeg || true ;;
    pacman) run sudo_maybe pacman -Sy --noconfirm ffmpeg ;;
    zypper) run sudo_maybe zypper --non-interactive in ffmpeg ;;
    *)      err "Unknown package manager"; return 1 ;;
  esac
}

ensure_ytdlp() {
  have yt-dlp && return 0
  warn "yt-dlp not found. Attempting distro install…"
  local mgr ok=false; mgr=$(detect_pkg) || true
  sudo_warmup || true
  case "$mgr" in
    apt)    run sudo_maybe apt-get -y install yt-dlp && ok=true ;;
    dnf)    run sudo_maybe dnf -y install yt-dlp && ok=true ;;
    yum)    run sudo_maybe yum -y install yt-dlp && ok=true || true ;;
    pacman) run sudo_maybe pacman -Sy --noconfirm yt-dlp && ok=true ;;
    zypper) run sudo_maybe zypper --non-interactive in yt-dlp && ok=true || true ;;
  esac
  if [[ $ok != true ]]; then
    warn "Falling back to pip (user install)."
    ensure_pip3 || return 1
    run pip3 install --user -U yt-dlp
    [[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"
    have yt-dlp || { err "yt-dlp still not found; add ~/.local/bin to PATH"; return 1; }
  fi
}

ensure_yt_deps() { ensure_wget && ensure_python3 && ensure_ffmpeg && ensure_ytdlp; }

# Remove helper if downloaded in CWD
cleanup_downloaded_helper() {
  local f="${1:-}"
  [[ -n "$f" && -e "$f" ]] || return 0
  case "$f" in
    ./*) rm -f -- "$f" && ok "Removed helper: $f" ;;
    *)   : ;;
  esac
}

# ---------------- Actions ----------------
x27_sysinfo() {
  inf "Host: $(hostname)"; inf "User: $USER"
  inf "Kernel: $(uname -srmo 2>/dev/null || uname -sr)"
  inf "Uptime: $(uptime -p || true)"
  if source /etc/os-release 2>/dev/null; then inf "Distro: ${NAME:-Unknown} ${VERSION:-}"; else inf "Distro: Unknown"; fi
  echo; inf "CPU:";   lscpu 2>/dev/null | sed -n '1,8p' || true
  echo; inf "Memory:"; free -h || true
  echo; inf "Disk:";  df -hT --total | sed -n '1,10p' || true
}

x27_update() {
  local mgr; mgr=$(detect_pkg) || { err "No supported package manager."; return 1; }
  warn "This will update system packages using: $mgr"
  confirm "Proceed with system update?" || { warn "Canceled."; return 0; }
  sudo_warmup || true
  case "$mgr" in
    apt)    run sudo_maybe apt-get update; run sudo_maybe apt-get -y upgrade; run sudo_maybe apt-get -y autoremove ;;
    dnf)    run sudo_maybe dnf -y upgrade ;;
    yum)    run sudo_maybe yum -y update ;;
    pacman) run sudo_maybe pacman -Syu --noconfirm ;;
    zypper) run sudo_maybe zypper refresh; run sudo_maybe zypper update -y ;;
    *)      err "Unsupported package manager: $mgr"; return 1 ;;
  esac
  ok "System update complete."
}

x27_cleanup() {
  inf "Cleaning package caches and old logs where possible."
  confirm "Proceed with cleanup?" || { warn "Canceled."; return 0; }
  local mgr; mgr=$(detect_pkg) || true
  sudo_warmup || true
  case "$mgr" in
    apt)     run sudo_maybe apt-get -y autoremove; run sudo_maybe apt-get -y autoclean ;;
    dnf|yum) run sudo_maybe "$mgr" clean all -y ;;
    pacman)  run sudo_maybe paccache -r -k2 2>/dev/null || true ;;
    zypper)  run sudo_maybe zypper clean -a ;;
  esac
  if have journalctl && confirm "Vacuum systemd journal to 200M?"; then run sudo_maybe journalctl --vacuum-size=200M; fi
  ok "Cleanup done."
}

x27_debian_desktop_setup() {
  echo; inf "Debian Desktop Setup (CLI → KDE)"
  msg " - KDE Standard, Flatpak + Discover, fish/fastfetch/VLC, Flathub, cleanup, reboot"
  warn "Debian-focused. This will change desktop packages and may reboot."
  confirm "Run the Debian Desktop Setup now?" || { warn "Canceled."; return 0; }
  local runner=""
  if [[ -f "$DEBIAN_POST_LOCAL_FALLBACK" ]]; then
    inf "Found local: $DEBIAN_POST_LOCAL_FALLBACK"; runner="$DEBIAN_POST_LOCAL_FALLBACK"
  else
    ensure_wget || return 1
    inf "Downloading → ./$DEBIAN_POST_LOCAL_NAME"
    run bash -c "wget -qO '$DEBIAN_POST_LOCAL_NAME' '$DEBIAN_POST_URL'"
    run chmod +x "$DEBIAN_POST_LOCAL_NAME"
    runner="./$DEBIAN_POST_LOCAL_NAME"
  fi
  sudo_warmup || true
  inf "Executing: $runner"
  run sudo_maybe bash "$runner"
  cleanup_downloaded_helper "$runner"
  ok "Debian Desktop Setup complete (system may reboot)."
}

x27_yt_downloader() {
  echo; inf "YT Downloader (local script)"
  msg " - yt-dlp + ffmpeg; downloads to ./YT-Downloads"
  local fname="YT-Downloader-Cli.py" fetched="false"
  if ! [[ -f "$fname" ]]; then
    ensure_wget || return 1
    inf "Fetching → ./$fname"
    run bash -c "wget -qO '$fname' '$YTDL_PY_URL'"
    fetched="true"
  fi
  if ! have yt-dlp || ! have ffmpeg || ! have python3; then
    warn "Ensuring prerequisites…"
    ensure_yt_deps || { [[ "$fetched" == "true" ]] && rm -f "$fname"; return 1; }
  fi
  inf "Launching: python3 $fname"
  run python3 "$fname" || true
  [[ "$fetched" == "true" ]] && rm -f -- "$fname" && ok "Removed helper: ./$fname"
  ok "Done. Files → ./YT-Downloads"
}

x27_virtualization_setup() {
  echo; inf "Virtualization Setup (KVM/QEMU + virt-manager)"
  msg " - Installs QEMU/KVM, libvirt, virt-manager; enables libvirtd; NAT; group access"
  confirm "Proceed with Virtualization Setup?" || { warn "Canceled."; return 0; }
  local runner=""
  if [[ -f "$VIRT_LOCAL_FALLBACK" ]]; then
    inf "Found local: $VIRT_LOCAL_FALLBACK"; runner="$VIRT_LOCAL_FALLBACK"
  else
    ensure_wget || return 1
    inf "Downloading → ./$VIRT_LOCAL_NAME"
    run bash -c "wget -qO '$VIRT_LOCAL_NAME' '$VIRT_URL'"
    run chmod +x "$VIRT_LOCAL_NAME"
    runner="./$VIRT_LOCAL_NAME"
  fi
  sudo_warmup || true
  inf "Executing: $runner"
  run sudo_maybe bash "$runner"
  cleanup_downloaded_helper "$runner"
  ok "Virtualization ready. Try: virt-manager"
}

x27_server_updater() {
  echo; inf "Deploy Server Updater"
  msg " - Universal updater (update-system) + optional cron (auto-reboot)"
  confirm "Proceed with Server Updater setup?" || { warn "Canceled."; return 0; }
  ensure_wget || return 1
  inf "Downloading → ./$SERVER_UPDATER_LOCAL_NAME"
  run bash -c "wget -qO '$SERVER_UPDATER_LOCAL_NAME' '$SERVER_UPDATER_URL'"
  run chmod +x "$SERVER_UPDATER_LOCAL_NAME"
  sudo_warmup || true
  inf "Executing: sudo bash $SERVER_UPDATER_LOCAL_NAME"
  run sudo_maybe bash "$SERVER_UPDATER_LOCAL_NAME"
  cleanup_downloaded_helper "./$SERVER_UPDATER_LOCAL_NAME"
  ok "Server Updater deployed."
}

x27_docker_install() {
  echo; inf "Docker Install"
  msg " - Detects Debian/RHEL; installs Docker Engine + plugins; adds user to docker group; optional Portainer"
  confirm "Proceed with Docker Install?" || { warn "Canceled."; return 0; }
  ensure_wget || return 1
  inf "Downloading → ./$DOCKER_INSTALL_LOCAL_NAME"
  run bash -c "wget -qO '$DOCKER_INSTALL_LOCAL_NAME' '$DOCKER_INSTALL_URL'"
  run chmod +x "$DOCKER_INSTALL_LOCAL_NAME"
  sudo_warmup || true
  inf "Executing: sudo bash $DOCKER_INSTALL_LOCAL_NAME"
  run sudo_maybe bash "$DOCKER_INSTALL_LOCAL_NAME"
  cleanup_downloaded_helper "./$DOCKER_INSTALL_LOCAL_NAME"
  ok "Docker install finished (log out/in may be required for group changes)."
}

x27_fedora_postsetup() {
  echo; inf "Fedora Post-Setup"
  msg " - RPM Fusion, codecs, KDE bits, etc."
  if source /etc/os-release 2>/dev/null; then
    local base="${ID_LIKE:-}${ID:-}"
    if [[ "$base" != *"fedora"* && "$base" != *"rhel"* ]]; then
      warn "Detected non-Fedora/RHEL base. This script targets Fedora."
      confirm "Continue anyway?" || { warn "Canceled."; return 0; }
    fi
  fi
  confirm "Proceed with Fedora Post-Setup?" || { warn "Canceled."; return 0; }
  ensure_wget || return 1
  inf "Downloading → ./$FEDORA_POST_LOCAL_NAME"
  run bash -c "wget -qO '$FEDORA_POST_LOCAL_NAME' '$FEDORA_POST_URL'"
  [[ -s "$FEDORA_POST_LOCAL_NAME" ]] || { err "Download failed or empty file: $FEDORA_POST_LOCAL_NAME"; return 1; }
  run chmod +x "$FEDORA_POST_LOCAL_NAME"
  sudo_warmup || true
  inf "Executing: sudo bash $FEDORA_POST_LOCAL_NAME"
  run sudo_maybe bash "$FEDORA_POST_LOCAL_NAME"
  cleanup_downloaded_helper "./$FEDORA_POST_LOCAL_NAME"
  ok "Fedora Post-Setup complete."
}

x27_brave_debloat() {
  echo; inf "Make Brave Great Again"
  msg " - Debloats Brave browser (privacy-focused tweaks)."
  confirm "Proceed with Brave debloat script?" || { warn "Canceled."; return 0; }
  ensure_wget || return 1
  inf "Downloading → ./$BRAVE_DEBLOAT_LOCAL_NAME"
  run bash -c "wget -qO '$BRAVE_DEBLOAT_LOCAL_NAME' '$BRAVE_DEBLOAT_URL'"
  [[ -s "$BRAVE_DEBLOAT_LOCAL_NAME" ]] || { err "Download failed or empty file: $BRAVE_DEBLOAT_LOCAL_NAME"; return 1; }
  run chmod +x "$BRAVE_DEBLOAT_LOCAL_NAME"
  sudo_warmup || true
  inf "Executing: sudo bash $BRAVE_DEBLOAT_LOCAL_NAME"
  run sudo_maybe bash "$BRAVE_DEBLOAT_LOCAL_NAME"
  cleanup_downloaded_helper "./$BRAVE_DEBLOAT_LOCAL_NAME"
  ok "Brave debloat complete."
}

# -------- Gaming: Proton-CachyOS installer --------
x27_proton_cachyos_installer() {
  echo; inf "Proton-CachyOS Installer"
  msg " - Downloads and runs the Proton-CachyOS installer."
  confirm "Proceed with Proton-CachyOS installer?" || { warn "Canceled."; return 0; }
  ensure_wget || return 1
  local runner="./$PROTON_CACHY_LOCAL_NAME"
  inf "Downloading → $runner"
  run bash -c "wget -qO '$runner' '$PROTON_CACHY_URL'"
  [[ -s "$runner" ]] || { err "Download failed or empty file: $runner"; return 1; }
  run chmod +x "$runner"
  sudo_warmup || true
  inf "Executing with sudo: $runner"
  run sudo_maybe bash "$runner"
  cleanup_downloaded_helper "$runner"
  ok "Proton-CachyOS installer finished."
}

# ---------------- Categorized registry ----------------
declare -a CATEGORY_IDS=("desktop" "system" "servers" "gaming")
declare -A CATEGORY_TITLES=(
  [desktop]="Linux Desktop"
  [system]="System"
  [servers]="Servers & Dev"
  [gaming]="Gaming"
)

declare -a ACTIONS_desktop=( "debian_desktop_setup" "virtualization_setup" "fedora_postsetup" "brave_debloat" )
declare -a ACTIONS_system=( "sysinfo" "update" "cleanup" "yt_downloader" )
declare -a ACTIONS_servers=( "docker_install" "server_updater" )
declare -a ACTIONS_gaming=( "proton_cachyos_installer" )

declare -A DESCRIPTIONS=(
  [sysinfo]="Show basic system info (CPU/mem/disk)."
  [update]="Update system packages (with confirmation)."
  [cleanup]="Clean caches/logs safely (with confirmation)."
  [debian_desktop_setup]="Debian Desktop Setup (CLI → KDE)."
  [yt_downloader]="YT Downloader: local script; installs deps if missing."
  [virtualization_setup]="Virtualization: KVM/QEMU, libvirt, virt-manager; enable libvirtd; NAT."
  [server_updater]="Deploy Server Updater: universal updater + optional cron."
  [docker_install]="Docker: Engine + plugins, docker group, optional Portainer."
  [fedora_postsetup]="Fedora Post-Setup: download and run Fedora-PostSetup.sh."
  [brave_debloat]="Brave Debloat: privacy/bloat tweaks."
  [proton_cachyos_installer]="Installer for Proton-CachyOS."
)

run_action() {
  local name="${1:-}"; shift || true
  case "$name" in
    sysinfo)                      x27_sysinfo "$@";;
    update)                       x27_update "$@";;
    cleanup)                      x27_cleanup "$@";;
    debian_desktop_setup)         x27_debian_desktop_setup "$@";;
    yt_downloader)                x27_yt_downloader "$@";;
    virtualization_setup)         x27_virtualization_setup "$@";;
    server_updater)               x27_server_updater "$@";;
    docker_install)               x27_docker_install "$@";;
    fedora_postsetup)             x27_fedora_postsetup "$@";;
    brave_debloat)                x27_brave_debloat "$@";;
    proton_cachyos_installer)     x27_proton_cachyos_installer "$@";;
    *) err "Unknown action: $name"; exit 1;;
  esac
}

print_actions_by_category() {
  local -a MENU_ACTIONS=()
  local idx=1 id act desc

  for id in "${CATEGORY_IDS[@]}"; do
    local title="${CATEGORY_TITLES[$id]}"
    local -n arr="ACTIONS_${id}"

    printf "%s┌─ %s%s%s ───────────────────────────┐%s\n" "$CYA" "$BOLD" "$title" "$RST" "$RST"
    if ((${#arr[@]})); then
      for act in "${arr[@]}"; do
        desc="${DESCRIPTIONS[$act]}"
        printf " %2d) %-24s %s\n" "$idx" "$act" "$desc"
        MENU_ACTIONS+=("$act")
        ((idx++))
      done
    else
      printf "    (no tools yet)\n"
    fi
    printf "└──────────────────────────────────────────┘%s\n\n" "$RST"
  done

  export MENU_ACTIONS_STR="${MENU_ACTIONS[*]}"
}

usage() {
  printf "%s%s%s v%s\n" "$BOLD" "$APP_NAME" "$RST" "$VERSION"
  echo "Minimal toolbox. Logs are deleted after each run."
  echo
  echo "Usage:"
  echo "  $APP_CMD                 # interactive menu"
  echo "  $APP_CMD <action>        # run a specific tool"
  echo
  print_actions_by_category
}

menu() {
  safe_clear
  printf "%s══════════════════════════════════════════════%s\n" "$CYA" "$RST"
  printf "%s%s%s %s- Your Linux Utility Toolbox%s\n" "$BOLD" "$APP_NAME" "$RST" "$DIM" "$RST"
  printf "%s══════════════════════════════════════════════%s\n\n" "$CYA" "$RST"

  print_actions_by_category
  IFS=' ' read -r -a MENU_ACTIONS <<<"$MENU_ACTIONS_STR"

  echo " q) quit"
  echo
  while true; do
    read -rp "Select an option: " choice || exit 0
    case "$choice" in
      q|Q) exit 0 ;;
      '' ) continue ;;
      *  )
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#MENU_ACTIONS[@]} )); then
          local action="${MENU_ACTIONS[$((choice-1))]}"
          echo; inf "Running: $action"
          run_action "$action"
          echo
          read -rp "Press Enter to continue..." _ || true
          safe_clear; menu; return
        else
          warn "Invalid selection."
        fi
        ;;
    esac
  done
}

main() {
  # Launcher is sudo-free; actions handle sudo on demand.
  if [[ $# -eq 0 ]]; then
    menu
    exit 0
  fi

  if [[ $# -eq 1 ]]; then
    run_action "$1"
    exit $?
  fi

  err "Invalid usage."
  usage
  exit 1
}

main "$@"
