#!/usr/bin/env bash
# XLinuxtools — sysinfo, update, cleanup, server_deploy, debian_desktop_setup (no log retention)
# Clean banner menu

set -Eeuo pipefail

APP_NAME="XLinuxtools"
APP_CMD="${0##*/}"
VERSION="0.5.1"

LOG_DIR="${XLT_LOG_DIR:-$HOME/.local/share/xlinuxtools/logs}"
CONF_DIR="${XLT_CONF_DIR:-$HOME/.config/xlinuxtools}"
DRY_RUN="${XLT_DRY_RUN:-false}"
NO_COLOR="${NO_COLOR:-}"

SERVERDEPLOY_URL="https://raw.githubusercontent.com/GamerX27/Homelab-X27/refs/heads/main/Serverdeploy.sh"
DEBIAN_POST_URL="https://raw.githubusercontent.com/GamerX27/X-Linuxtools/refs/heads/main/Scripts/Debian-Post-Installer.sh"
DEBIAN_POST_LOCAL_NAME="Debian-Post-Installer.sh"
DEBIAN_POST_LOCAL_FALLBACK="/Scripts/Debian-Post-Installer.sh"

# Colors
if [[ -z "${NO_COLOR}" ]]; then
  BOLD=$'\e[1m'; DIM=$'\e[2m'; RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'
  CYA=$'\e[36m'; RST=$'\e[0m'
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; CYA=""; RST=""
fi

mkdir -p "$LOG_DIR" "$CONF_DIR"
LOG_FILE="$LOG_DIR/$(date +%F_%H-%M-%S).log"

msg()  { printf "%s\n" "$*"; }
inf()  { printf "%sℹ%s %s\n" "$CYA" "$RST" "$*"; }
ok()   { printf "%s✔%s %s\n" "$GRN" "$RST" "$*"; }
warn() { printf "%s!%s %s\n"  "$YLW" "$RST" "$*"; }
err()  { printf "%s✖%s %s\n" "$RED" "$RST" "$*" >&2; }
log()  { printf "[%(%F %T)T] %s\n" -1 "$*" >>"$LOG_FILE"; }

confirm() {
  local prompt="${1:-Are you sure?}"
  read -r -p "$prompt [y/N] " ans || true
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

sudo_maybe() {
  if [[ $EUID -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      sudo "$@"
    else
      err "This action requires root and sudo is not installed."
      return 1
    fi
  else
    "$@"
  fi
}

run() {
  log "RUN: $*"
  if [[ "$DRY_RUN" == "true" ]]; then
    warn "[dry-run] $*"
  else
    "$@"
  fi
}

detect_pkg() {
  if command -v apt-get >/dev/null 2>&1; then echo "apt"
  elif command -v dnf >/dev/null 2>&1; then echo "dnf"
  elif command -v yum >/dev/null 2>&1; then echo "yum"
  elif command -v pacman >/dev/null 2>&1; then echo "pacman"
  elif command -v zypper >/dev/null 2>&1; then echo "zypper"
  else echo "unknown"; return 1; fi
}

usage() {
  printf "%s%s%s v%s\n" "$BOLD" "$APP_NAME" "$RST" "$VERSION"
  echo "Minimal toolbox. Logs are deleted after each run."
  echo
  echo "Usage:"
  echo "  $APP_CMD                 # interactive menu"
  echo "  $APP_CMD <action>        # run a specific tool"
  echo "  $APP_CMD --help | --list | --version"
  echo "  $APP_CMD --dry-run <action>"
  echo
  echo "Actions:"
  list_actions
}

# -------- Actions --------
xlt_sysinfo() {
  inf "Host: $(hostname)"
  inf "User: $USER"
  inf "Kernel: $(uname -srmo 2>/dev/null || uname -sr)"
  inf "Uptime: $(uptime -p || true)"
  if source /etc/os-release 2>/dev/null; then
    inf "Distro: ${NAME:-Unknown} ${VERSION:-}"
  else
    inf "Distro: Unknown"
  fi
  echo
  inf "CPU:"
  lscpu 2>/dev/null | sed -n '1,8p' || true
  echo
  inf "Memory:"
  free -h || true
  echo
  inf "Disk:"
  df -hT --total | sed -n '1,10p' || true
}

xlt_update() {
  local mgr
  mgr="$(detect_pkg)" || { err "No supported package manager found."; return 1; }
  warn "This will update system packages using: $mgr"
  confirm "Proceed with system update?" || { warn "Canceled."; return 0; }
  case "$mgr" in
    apt)
      run sudo_maybe apt-get update
      run sudo_maybe apt-get -y upgrade
      run sudo_maybe apt-get -y autoremove
      ;;
    dnf)     run sudo_maybe dnf -y upgrade ;;
    yum)     run sudo_maybe yum -y update ;;
    pacman)  run sudo_maybe pacman -Syu --noconfirm ;;
    zypper)  run sudo_maybe zypper refresh && run sudo_maybe zypper update -y ;;
    *)       err "Unsupported package manager: $mgr"; return 1 ;;
  esac
  ok "System update complete."
}

xlt_cleanup() {
  inf "Cleaning package caches and old logs where possible."
  if ! confirm "Proceed with cleanup?"; then warn "Canceled."; return 0; fi

  local mgr
  mgr="$(detect_pkg)" || true
  case "$mgr" in
    apt)     run sudo_maybe apt-get -y autoremove; run sudo_maybe apt-get -y autoclean ;;
    dnf|yum) run sudo_maybe "$mgr" clean all -y ;;
    pacman)  run sudo_maybe paccache -r -k2 2>/dev/null || true ;;
    zypper)  run sudo_maybe zypper clean -a ;;
  esac

  if command -v journalctl >/dev/null 2>&1; then
    if confirm "Vacuum systemd journal to 200M?"; then
      run sudo_maybe journalctl --vacuum-size=200M
    fi
  fi

  ok "Cleanup done."
}

xlt_server_deploy() {
  echo
  inf "X27 ServerDeploy"
  msg " - Installs Docker from the official Docker repository"
  msg " - Optional Portainer installation"
  msg " - Adds an updater that focuses on updating the OS and Docker containers"
  msg " - Source script: $SERVERDEPLOY_URL"
  echo
  warn "Tested on Debian — NOT guaranteed to work on Ubuntu."
  warn "This will download and execute a remote script."
  if ! confirm "Proceed knowing this is tested on Debian and may not work on Ubuntu?"; then
    warn "Canceled."
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    run bash -c "curl -fsSL '$SERVERDEPLOY_URL' | bash"
  elif command -v wget >/dev/null 2>&1; then
    run bash -c "wget -qO- '$SERVERDEPLOY_URL' | bash"
  else
    err "Neither curl nor wget found. Please install one, then retry."
    return 1
  fi
  ok "ServerDeploy finished."
}

xlt_debian_desktop_setup() {
  echo
  inf "Debian Desktop Setup (CLI → KDE)"
  msg " - Installs KDE Standard desktop"
  msg " - Installs Flatpak + Discover Flatpak backend"
  msg " - Installs fish, fastfetch, VLC"
  msg " - Adds Flathub, cleans APT"
  msg " - Removes /etc/network/interfaces and reboots"
  echo
  warn "Debian-focused. This will make desktop changes and trigger a reboot."
  if ! confirm "Run the Debian Desktop Setup now? (KDE, Flatpak, fish/fastfetch/VLC, Flathub, cleanup, reboot)"; then
    warn "Canceled."
    return 0
  fi

  local runner=""
  if [[ -f "$DEBIAN_POST_LOCAL_FALLBACK" ]]; then
    inf "Found local script at $DEBIAN_POST_LOCAL_FALLBACK"
    runner="$DEBIAN_POST_LOCAL_FALLBACK"
  else
    if ! command -v wget >/dev/null 2>&1; then
      warn "wget not found. Installing wget (Debian/apt only)."
      if [[ "$(detect_pkg)" == "apt" ]]; then
        run sudo_maybe apt-get update
        run sudo_maybe apt-get -y install wget
      else
        err "wget is required and could not be auto-installed."
        return 1
      fi
    fi
    inf "Downloading script to current directory: ./$DEBIAN_POST_LOCAL_NAME"
    run bash -c "wget -qO '$DEBIAN_POST_LOCAL_NAME' '$DEBIAN_POST_URL'"
    run chmod +x "$DEBIAN_POST_LOCAL_NAME"
    runner="./$DEBIAN_POST_LOCAL_NAME"
  fi

  inf "Executing: $runner"
  run sudo_maybe bash "$runner"
  ok "Debian Desktop Setup complete (system may reboot)."
}

# -------- Registration --------
declare -a ACTIONS=( "sysinfo" "update" "cleanup" "server_deploy" "debian_desktop_setup" )
declare -a DESCRIPTIONS=(
  "Show basic system information (CPU/mem/disk)."
  "Update system packages (asks for confirmation)."
  "Clean caches/logs safely (asks for confirmation)."
  "X27 ServerDeploy: install Docker (official repo), optional Portainer, and an updater for OS & containers."
  "Debian Desktop Setup (CLI→KDE): Install KDE, Flatpak, fish/fastfetch/VLC, Flathub, cleanup, reboot."
)

list_actions() {
  local i
  for (( i=0; i<${#ACTIONS[@]}; i++ )); do
    printf "  %-20s %s\n" "${ACTIONS[$i]}" "${DESCRIPTIONS[$i]}"
  done
}

run_action() {
  local name="$1"; shift || true
  case "$name" in
    sysinfo)              xlt_sysinfo "$@";;
    update)               xlt_update "$@";;
    cleanup)              xlt_cleanup "$@";;
    server_deploy)        xlt_server_deploy "$@";;
    debian_desktop_setup) xlt_debian_desktop_setup "$@";;
    *) err "Unknown action: $name"; exit 1;;
  esac
}

# -------- Menu --------
menu() {
  clear
  echo "${CYA}============================================${RST}"
  echo "${BOLD}${APP_NAME}${RST} ${DIM}- Your Linux Utility Toolbox${RST}"
  echo "${CYA}============================================${RST}"
  echo
  local i
  for (( i=0; i<${#ACTIONS[@]}; i++ )); do
    printf "%2d) %-20s %s\n" "$((i+1))" "${ACTIONS[$i]}" "${DESCRIPTIONS[$i]}"
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
          echo; inf "Running: $action"; run_action "$action"; echo
          read -rp "Press Enter to continue..." _ || true
          clear; menu; return
        else
          warn "Invalid selection."
        fi
        ;;
    esac
  done
}

# -------- Cleanup Logs on Exit --------
cleanup_logs() { [[ -f "$LOG_FILE" ]] && rm -f "$LOG_FILE"; }
trap cleanup_logs EXIT

# -------- CLI --------
main() {
  if [[ $# -eq 0 ]]; then menu; exit 0; fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) usage; exit 0 ;;
      --version) echo "$APP_NAME $VERSION"; exit 0 ;;
      --list)    list_actions; exit 0 ;;
      --dry-run) DRY_RUN="true"; shift; continue ;;
      -*)
        err "Unknown option: $1"; usage; exit 1 ;;
      *)
        run_action "$1" "${@:2}"; exit $? ;;
    esac
  done
}
main "$@"
