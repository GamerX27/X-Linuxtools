#!/usr/bin/env bash
# X27 — sysinfo, update, cleanup, server_deploy, debian_desktop_setup, yt_downloader, virtualization_setup
# Clean banner menu • logs deleted after each run

set -Eeuo pipefail

APP_NAME="X27"
APP_CMD="${0##*/}"
VERSION="0.6.5-integrated"

LOG_DIR="${X27_LOG_DIR:-$HOME/.local/share/x27/logs}"
CONF_DIR="${X27_CONF_DIR:-$HOME/.config/x27}"
DRY_RUN="${X27_DRY_RUN:-false}"
NO_COLOR="${NO_COLOR:-}"

SERVERDEPLOY_URL="https://raw.githubusercontent.com/GamerX27/Homelab-X27/refs/heads/main/Serverdeploy.sh"  # legacy (unused now)
DEBIAN_POST_URL="https://raw.githubusercontent.com/GamerX27/X-Linuxtools/refs/heads/main/Scripts/Debian-Post-Installer.sh"
DEBIAN_POST_LOCAL_NAME="Debian-Post-Installer.sh"
DEBIAN_POST_LOCAL_FALLBACK="/Scripts/Debian-Post-Installer.sh"

YTDL_PY_URL="https://raw.githubusercontent.com/GamerX27/YT-Downloader-Script/refs/heads/main/YT-Downloader-Cli.py"

VIRT_LOCAL_FALLBACK="/Scripts/Virtualization_Setup.sh"
VIRT_LOCAL_NAME="Virtualization_Setup.sh"
VIRT_URL="https://raw.githubusercontent.com/GamerX27/X-Linuxtools/refs/heads/main/Scripts/Virtualization_Setup.sh"

# Colors (respects NO_COLOR)
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

have() { command -v "$1" >/dev/null 2>&1; }

detect_pkg() {
  if   have apt-get; then echo "apt"
  elif have dnf;     then echo "dnf"
  elif have yum;     then echo "yum"
  elif have pacman;  then echo "pacman"
  elif have zypper;  then echo "zypper"
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

# -------- Dependency installers --------
ensure_wget() {
  if have wget; then return 0; fi
  warn "wget not found. Installing wget…"
  case "$(detect_pkg)" in
    apt)    run sudo_maybe apt-get update; run sudo_maybe apt-get -y install wget ;;
    dnf)    run sudo_maybe dnf -y install wget ;;
    yum)    run sudo_maybe yum -y install wget ;;
    pacman) run sudo_maybe pacman -Sy --noconfirm wget ;;
    zypper) run sudo_maybe zypper --non-interactive in wget ;;
    *)      err "Unknown package manager. Please install wget manually."; return 1 ;;
  esac
}

ensure_curl() {
  if have curl; then return 0; fi
  warn "curl not found. Installing curl…"
  case "$(detect_pkg)" in
    apt)    run sudo_maybe apt-get update; run sudo_maybe apt-get -y install curl ;;
    dnf)    run sudo_maybe dnf -y install curl ;;
    yum)    run sudo_maybe yum -y install curl ;;
    pacman) run sudo_maybe pacman -Sy --noconfirm curl ;;
    zypper) run sudo_maybe zypper --non-interactive in curl ;;
    *)      err "Unknown package manager. Please install curl manually."; return 1 ;;
  esac
}

ensure_python3() {
  if have python3; then return 0; fi
  warn "python3 not found. Installing python3…"
  case "$(detect_pkg)" in
    apt)    run sudo_maybe apt-get update; run sudo_maybe apt-get -y install python3 ;;
    dnf)    run sudo_maybe dnf -y install python3 ;;
    yum)    run sudo_maybe yum -y install python3 ;;
    pacman) run sudo_maybe pacman -Sy --noconfirm python ;;
    zypper) run sudo_maybe zypper --non-interactive in python3 ;;
    *)      err "Unknown package manager. Please install python3 manually."; return 1 ;;
  esac
}

ensure_pip3() {
  if have pip3; then return 0; fi
  warn "pip3 not found. Installing pip3…"
  case "$(detect_pkg)" in
    apt)    run sudo_maybe apt-get -y install python3-pip ;;
    dnf)    run sudo_maybe dnf -y install python3-pip ;;
    yum)    run sudo_maybe yum -y install python3-pip ;;
    pacman) run sudo_maybe pacman -Sy --noconfirm python-pip ;;
    zypper) run sudo_maybe zypper --non-interactive in python3-pip ;;
    *)      err "Unknown package manager. Please install pip3 manually."; return 1 ;;
  esac
}

ensure_ffmpeg() {
  if have ffmpeg; then return 0; fi
  warn "ffmpeg not found. Installing ffmpeg…"
  case "$(detect_pkg)" in
    apt)    run sudo_maybe apt-get -y install ffmpeg ;;
    dnf)    run sudo_maybe dnf -y install ffmpeg ;;
    yum)    run sudo_maybe yum -y install ffmpeg || true ;;
    pacman) run sudo_maybe pacman -Sy --noconfirm ffmpeg ;;
    zypper) run sudo_maybe zypper --non-interactive in ffmpeg ;;
    *)      err "Unknown package manager. Please install ffmpeg manually."; return 1 ;;
  esac
}

ensure_ytdlp() {
  if have yt-dlp; then return 0; fi
  warn "yt-dlp not found. Attempting to install from distro repos…"
  local ok="false"
  case "$(detect_pkg)" in
    apt)    run sudo_maybe apt-get -y install yt-dlp && ok="true" ;;
    dnf)    run sudo_maybe dnf -y install yt-dlp && ok="true" ;;
    yum)    run sudo_maybe yum -y install yt-dlp && ok="true" || true ;;
    pacman) run sudo_maybe pacman -Sy --noconfirm yt-dlp && ok="true" ;;
    zypper) run sudo_maybe zypper --non-interactive in yt-dlp && ok="true" || true ;;
    *)      ok="false" ;;
  esac
  if [[ "$ok" != "true" ]]; then
    warn "Falling back to user install via pip3 (no sudo)."
    ensure_pip3 || return 1
    run pip3 install --user -U yt-dlp
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
      export PATH="$HOME/.local/bin:$PATH"
      warn "Temporarily added ~/.local/bin to PATH for this session."
    fi
    if ! have yt-dlp; then
      err "yt-dlp still not found after pip install. Please add ~/.local/bin to PATH."
      return 1
    fi
  fi
}

ensure_yt_deps() {
  ensure_wget    || return 1
  ensure_python3 || return 1
  ensure_ffmpeg  || return 1
  ensure_ytdlp   || return 1
  ok "All YT Downloader dependencies are present."
}

# -------- Actions --------
x27_sysinfo() {
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
  inf "CPU:";    lscpu 2>/dev/null | sed -n '1,8p' || true
  echo
  inf "Memory:"; free -h || true
  echo
  inf "Disk:";   df -hT --total | sed -n '1,10p' || true
}

x27_update() {
  local mgr; mgr="$(detect_pkg)" || { err "No supported package manager found."; return 1; }
  warn "This will update system packages using: $mgr"
  confirm "Proceed with system update?" || { warn "Canceled."; return 0; }
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
  if ! confirm "Proceed with cleanup?"; then warn "Canceled."; return 0; fi
  local mgr; mgr="$(detect_pkg)" || true
  case "$mgr" in
    apt)     run sudo_maybe apt-get -y autoremove; run sudo_maybe apt-get -y autoclean ;;
    dnf|yum) run sudo_maybe "$mgr" clean all -y ;;
    pacman)  run sudo_maybe paccache -r -k2 2>/dev/null || true ;;
    zypper)  run sudo_maybe zypper clean -a ;;
  esac
  if have journalctl; then
    if confirm "Vacuum systemd journal to 200M?"; then
      run sudo_maybe journalctl --vacuum-size=200M
    fi
  fi
  ok "Cleanup done."
}

# NOTE: server_deploy action fully replaced to run a dedicated Bash script (#!/bin/bash)
x27_server_deploy() {
  echo
  inf "X27 ServerDeploy (integrated)"
  msg " - Installs Docker via get.docker.com"
  msg " - Optional Portainer CE"
  msg " - Deploys /usr/local/bin/update helper (OS + Flatpak + Docker via Watchtower)"
  echo
  warn "This will download and execute Docker's official install script (get.docker.com)."
  if ! confirm "Proceed with integrated server deploy?"; then warn "Canceled."; return 0; fi

  ensure_curl || return 1

  # Build a temp script that uses #!/bin/bash as requested
  local tmp_script
  tmp_script="$(mktemp /tmp/x27_serverdeploy.XXXXXX.sh)"
  cat >"$tmp_script" <<'X27SERVERDEPLOY'
#!/bin/bash

GREEN="[0;32m"
RED="[0;31m"
CYAN="[0;36m"
BOLD="[1m"
NC="[0m"

print_banner() {
  echo -e "
[1;34m"
  echo "######################################################################"
  echo "#                                                                    #"
  echo "#                X27 Docker & Update Setup Script                    #"
  echo "#                                                                    #"
  echo "######################################################################"
  echo -e "[0m
"
}

print_success() { echo -e "${GREEN}$1${NC}"; }
print_error()   { echo -e "${RED}$1${NC}"; }

install_docker() {
  echo "Downloading Docker installation script..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  echo "Running Docker installation script..."
  sudo sh get-docker.sh
  if [ $? -eq 0 ]; then
    print_success "Docker installed successfully!"
  else
    print_error "Docker installation failed!"; exit 1
  fi
  rm -f get-docker.sh
}

install_portainer() {
  echo "Creating Docker volume for Portainer..."
  sudo docker volume create portainer_data
  echo "Running Portainer CE container..."
  sudo docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always \
    -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data \
    portainer/portainer-ce:latest
  if [ $? -eq 0 ]; then
    print_success "Portainer CE installed successfully!"
  else
    print_error "Portainer CE installation failed!"
  fi
}

install_update_script() {
  TARGET="/usr/local/bin/update"
  echo -e "${CYAN}${BOLD}📦 Deploying update script to $TARGET...${NC}"
  sudo tee "$TARGET" > /dev/null <<'EOF'
#!/bin/bash
GREEN="[0;32m"
CYAN="[0;36m"
RED="[0;31m"
BOLD="[1m"
NC="[0m"

echo -e "${CYAN}${BOLD}🧼 Starting full system update...${NC}"

if command -v dnf >/dev/null 2>&1; then PM="dnf"; elif command -v apt >/dev/null 2>&1; then PM="apt"; else echo -e "${RED}❌ No supported package manager found (dnf or apt).${NC}"; exit 1; fi

echo -e "${GREEN}📦 Updating system packages with $PM...${NC}"
if [ "$PM" = "dnf" ]; then sudo dnf upgrade --refresh -y; else sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y; fi

if command -v flatpak >/dev/null 2>&1; then echo -e "${GREEN}📦 Updating Flatpaks...${NC}"; flatpak update -y; fi

if command -v docker >/dev/null 2>&1; then
  CONTAINER_COUNT=$(sudo docker ps -a -q | wc -l)
  if [ "$CONTAINER_COUNT" -eq 0 ]; then echo -e "${CYAN}📭 No Docker containers found. Skipping Watchtower.${NC}"; else echo -e "${GREEN}🚀 Running Watchtower once to update containers...${NC}"; sudo docker run --rm -v /var/run/docker.sock:/var/run/docker.sock containrrr/watchtower --run-once --cleanup; fi
else
  echo -e "${CYAN}⚠️ Docker not installed. Skipping container updates.${NC}"
fi

echo -e "${BOLD}${GREEN}✅ System update completed successfully!${NC}"
EOF
  printf "%b❓ Make the script executable with chmod +x? [y/n]: %b" "${BOLD}" "${NC}" > /dev/tty
  IFS= read -r confirm < /dev/tty
  case "$confirm" in [Yy]*) sudo chmod +x "$TARGET"; echo -e "${GREEN}✅ Script is now executable. You can run it with: ${BOLD}update${NC}";; [Nn]*) echo -e "${RED}⚠️ Skipped chmod. You must run this manually if you want to execute the script:${NC}"; echo -e "${BOLD} sudo chmod +x $TARGET${NC}";; *) echo -e "${RED}Invalid choice. Defaulting to skip chmod.${NC}";; esac
}

print_banner

install_docker

if [[ -t 0 && -r /dev/tty ]]; then
  read -r -p "Do you want to install Portainer CE? (Y/y = Yes, N/n = No): " ans_portainer </dev/tty || ans_portainer="n"
else
  ans_portainer="n"
fi

case "$ans_portainer" in
  Y|y) install_portainer ;;
  N|n) echo "Skipping Portainer installation." ;;
  *)   echo "Invalid choice. Skipping Portainer installation." ;;
fi

install_update_script

echo; print_success "X27 Docker & Update Setup completed!"
X27SERVERDEPLOY

  chmod +x "$tmp_script"
  inf "Executing integrated server deploy script ($tmp_script)…"
  run bash "$tmp_script"
  rm -f "$tmp_script" || true
  ok "ServerDeploy finished."
}

x27_debian_desktop_setup() {
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
    warn "Canceled."; return 0
  fi

  local runner=""
  if [[ -f "$DEBIAN_POST_LOCAL_FALLBACK" ]]; then
    inf "Found local script: $DEBIAN_POST_LOCAL_FALLBACK"
    runner="$DEBIAN_POST_LOCAL_FALLBACK"
  else
    ensure_wget || return 1
    inf "Downloading script to current directory: ./$DEBIAN_POST_LOCAL_NAME"
    run bash -c "wget -qO '$DEBIAN_POST_LOCAL_NAME' '$DEBIAN_POST_URL'"
    run chmod +x "$DEBIAN_POST_LOCAL_NAME"
    runner="./$DEBIAN_POST_LOCAL_NAME"
  fi

  inf "Executing: $runner"
  run sudo_maybe bash "$runner"
  ok "Debian Desktop Setup complete (system may reboot)."
}

x27_yt_downloader() {
  echo
  inf "YT Downloader (local script)"
  msg " - Downloads videos/playlists as MP4 or MP3 using yt-dlp"
  msg " - Uses ffmpeg for merging/encoding"
  msg " - Script saved locally; downloads go to ./YT-Downloads"
  echo

  local fname="YT-Downloader-Cli.py"

  # If yt-dlp is present, SKIP any install prompts and just run the app.
  if have yt-dlp; then
    ok "yt-dlp detected — skipping dependency installation."
    if ! have python3; then
      err "python3 is not installed. Please install python3 and rerun."
      return 1
    fi
    if [[ ! -f "$fname" ]]; then
      if have wget; then
        inf "Fetching downloader to ./$fname"
        run bash -c "wget -qO '$fname' '$YTDL_PY_URL'"
      else
        err "wget not found to fetch the script automatically. Install wget or place $fname here."
        return 1
      fi
    else
      inf "Using existing $fname"
    fi
    inf "Launching downloader (python3 $fname)…"
    run python3 "$fname" || true
    ok "YT Downloader finished. Files are in ./YT-Downloads"
    return 0
  fi

  # yt-dlp missing -> show what else is missing and ask to install
  warn "yt-dlp not found."
  local missing=()
  have python3 || missing+=("python3")
  have ffmpeg  || missing+=("ffmpeg")
  missing+=("yt-dlp")
  have wget    || missing+=("wget")
  warn "Missing dependencies: ${missing[*]}"
  if ! confirm "Install missing dependencies now?"; then
    warn "Canceled because dependencies are missing."
    return 1
  fi

  ensure_yt_deps || return 1

  # Ensure the script file exists
  if [[ ! -f "$fname" ]]; then
    inf "Fetching downloader to ./$fname"
    run bash -c "wget -qO '$fname' '$YTDL_PY_URL'"
  else
    inf "Using existing $fname"
  fi

  inf "Launching downloader (python3 $fname)…"
  run python3 "$fname" || true
  ok "YT Downloader finished. Files are in ./YT-Downloads"
}

x27_virtualization_setup() {
  echo
  inf "Virtualization Setup (KVM/QEMU + virt-manager)"
  msg " - Installs QEMU/KVM, libvirt, and virt-manager"
  msg " - Updates package index; enables & starts libvirtd"
  msg " - Configures default NAT network"
  msg " - Adds your user to the libvirt group for VM management"
  echo
  if ! confirm "Proceed with Virtualization Setup?"; then
    warn "Canceled."; return 0
  fi

  local runner=""
  if [[ -f "$VIRT_LOCAL_FALLBACK" ]]; then
    inf "Found local script: $VIRT_LOCAL_FALLBACK"
    runner="$VIRT_LOCAL_FALLBACK"
  else
    ensure_wget || return 1
    inf "Downloading virtualization script to ./$VIRT_LOCAL_NAME"
    run bash -c "wget -qO '$VIRT_LOCAL_NAME' '$VIRT_URL'"
    run chmod +x "$VIRT_LOCAL_NAME"
    runner="./$VIRT_LOCAL_NAME"
  fi

  inf "Executing: $runner"
  run sudo_maybe bash "$runner"
  ok "Virtualization Setup complete. You can now run virt-manager."
}

# -------- Registration --------
declare -a ACTIONS=( "sysinfo" "update" "cleanup" "server_deploy" "debian_desktop_setup" "yt_downloader" "virtualization_setup" )
declare -a DESCRIPTIONS=(
  "Show basic system information (CPU/mem/disk)."
  "Update system packages (asks for confirmation)."
  "Clean caches/logs safely (asks for confirmation)."
  "X27 ServerDeploy: install Docker (official get.docker.com), optional Portainer, and update helper."
  "Debian Desktop Setup (CLI→KDE)."
  "YT Downloader: Local script; skips install if yt-dlp is present."
  "Virtualization Setup: KVM/QEMU, libvirt, virt-manager; enable libvirtd; NAT."
)

list_actions() {
  local i
  for (( i=0; i<${#ACTIONS[@]}; i++ )); do
    printf "  %-22s %s\n" "${ACTIONS[$i]}" "${DESCRIPTIONS[$i]}"
  done
}

run_action() {
  local name="$1"; shift || true
  case "$name" in
    sysinfo)              x27_sysinfo "$@";;
    update)               x27_update "$@";;
    cleanup)              x27_cleanup "$@";;
    server_deploy)        x27_server_deploy "$@";;
    debian_desktop_setup) x27_debian_desktop_setup "$@";;
    yt_downloader)        x27_yt_downloader "$@";;
    virtualization_setup) x27_virtualization_setup "$@";;
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
