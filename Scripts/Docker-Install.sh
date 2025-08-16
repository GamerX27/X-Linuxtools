#!/usr/bin/env bash
set -euo pipefail

# --- Helpers ---------------------------------------------------------------
log()  { echo -e "\033[1;34m[*]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
err()  { echo -e "\033[1;31m[x]\033[0m $*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Missing required command: $1"; exit 1; }
}

invoking_user() {
  # Prefer the user who invoked sudo; fallback to $USER
  if [[ -n "${SUDO_USER-}" && "${SUDO_USER}" != "root" ]]; then
    echo "${SUDO_USER}"
  else
    echo "${USER}"
  fi
}

add_user_to_docker_group() {
  local user_to_add
  user_to_add="$(invoking_user)"
  log "Ensuring 'docker' group exists and adding user '${user_to_add}' to it..."
  sudo groupadd -f docker
  sudo usermod -aG docker "${user_to_add}"
  warn "You'll need to log out/in (or run 'newgrp docker') for group changes to take effect."
}

post_install_success() {
  # Verify and then offer Portainer
  log "Verifying Docker installation..."
  sudo docker --version
  sudo docker compose version || true

  # Add user to docker group
  add_user_to_docker_group

  echo
  read -r -p "Would you like to install Portainer (a lightweight Docker management UI)? [y/N]: " REPLY
  REPLY="${REPLY:-N}"
  if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    log "Installing Portainer CE (LTS)..."
    sudo docker volume create portainer_data >/dev/null
    sudo docker run -d \
      -p 8000:8000 -p 9443:9443 \
      --name portainer \
      --restart=always \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v portainer_data:/data \
      portainer/portainer-ce:lts
    log "Portainer installed. Open https://localhost:9443 to finish setup."
    warn "If accessing remotely, ensure firewall rules allow TCP 9443/8000."
  else
    log "Skipping Portainer installation."
    echo "Docker installed on your system!"
  fi
}

# --- Detect distro family ---------------------------------------------------
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  err "/etc/os-release not found; cannot detect distribution."
  exit 1
fi

ID_LIKE_LOWER="$(echo "${ID_LIKE:-$ID}" | tr '[:upper:]' '[:lower:]')"
ID_LOWER="$(echo "${ID:-}" | tr '[:upper:]' '[:lower:]')"

is_debian_like=false
is_rhel_like=false

case "$ID_LOWER" in
  debian|ubuntu|raspbian|linuxmint|pop) is_debian_like=true ;;
  rhel|centos|rocky|almalinux|fedora|ol) is_rhel_like=true ;;
esac
[[ "$ID_LIKE_LOWER" == *"debian"*  ]] && is_debian_like=true
[[ "$ID_LIKE_LOWER" == *"rhel"* || "$ID_LIKE_LOWER" == *"fedora"* || "$ID_LIKE_LOWER" == *"centos"* ]] && is_rhel_like=true

if ! $is_debian_like && ! $is_rhel_like; then
  err "Unsupported/undetected distro. ID=$ID, ID_LIKE=${ID_LIKE:-N/A}"
  exit 1
fi

# --- Debian-based install ---------------------------------------------------
install_docker_debian() {
  require_cmd sudo
  require_cmd curl
  require_cmd dpkg
  log "Detected Debian-like system ($PRETTY_NAME)."

  log "Updating package index..."
  sudo apt-get update -y

  log "Installing prerequisites..."
  sudo apt-get install -y ca-certificates curl gnupg lsb-release

  log "Setting up Docker's GPG key..."
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  local arch codename
  arch="$(dpkg --print-architecture)"
  codename="${VERSION_CODENAME:-}"
  if [[ -z "$codename" ]]; then
    if command -v lsb_release >/dev/null 2>&1; then
      codename="$(lsb_release -cs)"
    else
      err "Could not determine distro codename."
      exit 1
    fi
  fi

  log "Adding Docker APT repo (arch=${arch}, codename=${codename})..."
  echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${codename} stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  log "Updating package index (with Docker repo)..."
  sudo apt-get update -y

  log "Installing Docker Engine and plugins..."
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  log "Enabling and starting Docker service..."
  sudo systemctl enable --now docker

  post_install_success
}

# --- RHEL-based install -----------------------------------------------------
install_docker_rhel() {
  require_cmd sudo
  if ! command -v dnf >/dev/null 2>&1; then
    err "dnf not found. On very old systems, install dnf or use yum-based instructions."
    exit 1
  fi
  log "Detected RHEL-like system ($PRETTY_NAME)."

  log "Removing conflicting packages (docker, podman, runc)..."
  sudo dnf remove -y \
    docker docker-client docker-client-latest docker-common \
    docker-latest docker-latest-logrotate docker-logrotate docker-engine \
    podman runc || true

  log "Installing dnf-plugins-core..."
  sudo dnf -y install dnf-plugins-core

  log "Adding Docker CE repo..."
  sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo

  log "Installing Docker Engine and plugins..."
  sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  log "Enabling and starting Docker service..."
  sudo systemctl enable --now docker

  post_install_success
}

# --- Dispatch --------------------------------------------------------------
if $is_debian_like; then
  install_docker_debian
elif $is_rhel_like; then
  install_docker_rhel
fi

log "All done."
