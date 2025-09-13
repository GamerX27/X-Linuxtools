#!/usr/bin/env bash
# X27 — sysinfo, update, cleanup, debian_desktop_setup, yt_downloader,
#        virtualization_setup, server_updater, docker_install,
#        fedora_postsetup, brave_debloat
# Clean banner menu • logs deleted after each run

# ---------------- Strict mode ----------------
set -Eeuo pipefail
IFS=$' \t\n'

# ---------------- Metadata ----------------
APP_NAME="X27"
APP_CMD="${0##*/}"
VERSION="0.7.2"

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

run() {
  log "RUN: $*"
  "$@"
}

confirm() {
  local prompt="${1:-Are you sure?}" ans
  read -r -p "$prompt [y/N] " ans || true
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

# ---------------- Base deps ----------------
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
  local deps=(wget curl git sudo) missing=() mgr
  for d in "${deps[@]}"; do have "$d" || missing+=("$d"); done
  if [[ ${#missing[@]} -eq 0 ]]; then ok "Base deps present: wget curl git sudo"; return 0; fi
  mgr=$(detect_pkg) || { err "Unsupported package manager. Please install: ${missing[*]}"; return 1; }
  if [[ $EUID -ne 0 && " ${missing[*]} " == *" sudo "* ]]; then
    err "'sudo' is missing and you are not root. Re-run as root to install: ${missing[*]}"; return 1
  fi
  inf "Installing missing base deps via $mgr: ${missing[*]}"
  install_with_mgr "$mgr" "${missing[@]}" || { err "Failed to install: ${missing[*]}"; return 1; }
  ok "Base dependencies installed."
}

# ---------------- Dependency helpers ----------------
ensure_wget() { have wget && return 0 || { warn "wget not found. Installing…"; base_deps_check_install; }; }
ensure_python3() {
  have python3 && return 0
  warn "python3 not found. Installing…"
  local mgr; mgr=$(detect_pkg) || { err "Unknown package manager"; return 1; }
  case "$mgr" in
    apt) run sudo_maybe apt-get update; run sudo_maybe apt-get -y install python3 ;;
    dnf) run sudo_maybe dnf -y install python3 ;;
    yum) run sudo_maybe yum -y install python3 ;;
    pacman) run sudo_maybe pacman -Sy --noconfirm python ;;
    zypper) run sudo_maybe zypper --non-interactive in python3 ;;
    *) err "Unknown package manager"; return 1 ;;
  esac
}
ensure_pip3() {
  have pip3 && return 0
  warn "pip3 not found. Installing…"
  local mgr; mgr=$(detect_pkg) || { err "Unknown package manager"; return 1; }
  case "$mgr" in
    apt) run sudo_maybe apt-get -y install python3-pip ;;
    dnf) run sudo_maybe dnf -y install python3-pip ;;
    yum) run sudo_maybe yum -y install python3-pip ;;
    pacman) run sudo_maybe pacman -Sy --noconfirm python-pip ;;
    zypper) run sudo_maybe zypper --non-interactive in python3-pip ;;
    *) err "Unknown package manager"; return 1 ;;
  esac
}
ensure_ffmpeg() {
  have ffmpeg && return 0
  warn "ffmpeg not found. Installing…"
  local mgr; mgr=$(detect_pkg) || { err "Unknown package manager"; return 1; }
  case "$mgr" in
    apt) run sudo_maybe apt-get -y install ffmpeg ;;
    dnf) run sudo_maybe dnf -y install ffmpeg ;;
    yum) run sudo_maybe yum -y install ffmpeg || true ;;
    pacman) run sudo_maybe pacman -Sy --noconfirm ffmpeg ;;
    zypper) run sudo_maybe zypper --non-interactive in ffmpeg ;;
    *) err "Unknown package manager"; return 1 ;;
  esac
}
ensure_ytdlp() {
  have yt-dlp && return 0
  warn "yt-dlp not found. Attempting distro install…"
  local mgr ok=false; mgr=$(detect_pkg) || true
  case "$mgr" in
    apt) run sudo_maybe apt-get -y install yt-dlp && ok=true ;;
    dnf) run sudo_maybe dnf -y install yt-dlp && ok=true ;;
    yum) run sudo_maybe yum -y install yt-dlp && ok=true || true ;;
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

# ---------------- Actions ----------------
# (your existing x27_sysinfo, x27_update, x27_cleanup, etc go here unchanged)

# ---------------- Registration ----------------
declare -a ACTIONS=(
  "sysinfo" "update" "cleanup" "debian_desktop_setup" "yt_downloader"
  "virtualization_setup" "server_updater" "docker_install" "fedora_postsetup" "brave_debloat"
)

declare -a DESCRIPTIONS=(
  "Show basic system info (CPU/mem/disk)."
  "Update system packages (with confirmation)."
  "Clean caches/logs safely (with confirmation)."
  "Debian Desktop Setup (CLI → KDE)."
  "YT Downloader: local script; installs deps if missing."
  "Virtualization: KVM/QEMU, libvirt, virt-manager; enable libvirtd; NAT."
  "Deploy Server Updater: universal updater + optional cron."
  "Docker: Engine + plugins, docker group, optional Portainer."
  "Fedora Post-Setup: download and run Fedora-PostSetup.sh."
  "Brave Debloat: download and run privacy/bloat tweaks."
)

list_actions() {
  local i
  for (( i=0; i<${#ACTIONS[@]}; i++ )); do
    printf "  %-22s %s\n" "${ACTIONS[$i]}" "${DESCRIPTIONS[$i]}"
  done
}

run_action() {
  local name="${1:-}"; shift || true
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
    brave_debloat)        x27_brave_debloat "$@";;
    *) err "Unknown action: $name"; exit 1;;
  esac
}

usage() {
  printf "%s%s%s v%s\n" "$BOLD" "$APP_NAME" "$RST" "$VERSION"
  echo "Minimal toolbox. Logs are deleted after each run."
  echo
  echo "Usage:"
  echo "  $APP_CMD                 # interactive menu"
  echo "  $APP_CMD <action>        # run a specific tool"
  echo
  echo "Actions:"
  list_actions
}

menu() {
  safe_clear
  echo "${CYA}============================================${RST}"
  echo "${BOLD}${APP_NAME}${RST} ${DIM}- Your Linux Utility Toolbox${RST}"
  echo "${CYA}============================================${RST}"
  echo
  local i
  for (( i=0; i<${#ACTIONS[@]}; i++ )); do
    printf "%2d) %-22s %s\n" "$((i+1))" "${ACTIONS[$i]}" "${DESCRIPTIONS[$i]}"
  done
  echo " q) quit"
  echo
  while true; do
    read -rp "Select an option: " choice || exit 0
    case "$choice" in
      q|Q) exit 0 ;;
      '' ) continue ;;
      *  )
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#ACTIONS[@]} )); then
          local action="${ACTIONS[$((choice-1))]}"
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
  base_deps_check_install || exit 1

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
