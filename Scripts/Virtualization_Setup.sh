#!/bin/bash
# Universal QEMU/KVM + virt-manager installer for apt/dnf/pacman
# - Installs QEMU, KVM, libvirt, virt-manager
# - Optional extras (SPICE/USB redirection) only where available
# - Sets up default NAT network; optional bridged network
# - Adds current user to libvirt & kvm groups
# Run as root (sudo).

set -euo pipefail

detect_distro() {
  echo "Detecting Linux distribution..."
  if [[ -f /etc/os-release ]]; then . /etc/os-release; fi
  case "${ID:-unknown}" in
    ubuntu|debian) PKG_MGR="apt" ;;
    fedora)        PKG_MGR="dnf" ;;
    centos|rocky|almalinux|alma|rhel|ol) PKG_MGR="dnf" ;;
    arch|manjaro|endeavouros|arcolinux)  PKG_MGR="pacman" ;;
    *)  # try ID_LIKE
      case "${ID_LIKE:-}" in
        *debian*) PKG_MGR="apt" ;;
        *rhel*|*fedora*) PKG_MGR="dnf" ;;
        *arch*) PKG_MGR="pacman" ;;
        *) echo "Unsupported distribution."; exit 1 ;;
      esac
      ;;
  esac
  echo "Detected package manager: $PKG_MGR"
}

update_system() {
  echo "Updating package metadata..."
  case "$PKG_MGR" in
    apt)    apt-get update -y ;;
    dnf)    dnf -y update ;;
    pacman) pacman -Sy --noconfirm && pacman -Su --noconfirm ;;
  esac
}

install_packages() {
  echo "Installing QEMU/KVM, libvirt, and virt-manager..."
  case "$PKG_MGR" in
    apt)
      # Core packages (NO usbredir here; not required for local USB passthrough)
      apt-get install -y \
        qemu-kvm qemu-utils libvirt-daemon-system libvirt-clients virt-manager \
        bridge-utils dnsmasq ebtables
      # Optional SPICE client libs aren’t needed for virt-manager; skip to avoid repo issues
      ;;

    dnf)
      # Enable EPEL on RHEL-like if present (optional)
      if [[ "${ID:-}" =~ (centos|rocky|almalinux|alma|rhel|ol) ]]; then
        dnf install -y epel-release || true
      fi
      dnf install -y qemu-kvm qemu-img libvirt virt-install virt-manager \
        bridge-utils dnsmasq ebtables || true
      # Optional extras (best-effort)
      dnf install -y spice-gtk usbredir || true
      ;;

    pacman)
      pacman -S --needed --noconfirm qemu-full libvirt virt-manager dnsmasq bridge-utils ebtables
      # Optional extras (best-effort)
      pacman -S --needed --noconfirm spice-gtk usbredir openbsd-netcat vde2 || true
      ;;
  esac
  echo "Package installation completed."
}

configure_default_network() {
  echo "Configuring default libvirt NAT network..."
  systemctl restart libvirtd || true
  # define/start 'default' NAT network if needed
  if ! virsh net-info default &>/dev/null; then
    if [[ -f /usr/share/libvirt/networks/default.xml ]]; then
      virsh net-define /usr/share/libvirt/networks/default.xml || true
    else
      echo "Defining default NAT network from inline XML..."
      virsh net-define <(cat <<'EOF'
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
EOF
) || true
    fi
  fi
  virsh net-start default 2>/dev/null || true
  virsh net-autostart default 2>/dev/null || true
  echo "NAT network 'default' active on virbr0."
}

setup_bridged_network() {
  echo "Setting up bridged networking (br0)..."
  case "$PKG_MGR" in
    apt)    apt-get install -y bridge-utils ;;
    dnf)    dnf install -y bridge-utils || true ;;
    pacman) pacman -S --needed --noconfirm bridge-utils ;;
  esac

  PRIMARY_IF=$(ip -o route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++){ if($i=="dev"){print $(i+1); exit}}}')
  if [[ -z "${PRIMARY_IF:-}" ]]; then
    echo "Could not detect primary interface. Skipping bridge setup."
    return
  fi
  echo "Primary interface: $PRIMARY_IF"

  if command -v nmcli &>/dev/null && systemctl is-active --quiet NetworkManager; then
    echo "Using NetworkManager to create bridge br0..."
    nmcli device disconnect "$PRIMARY_IF" || true
    nmcli connection add type bridge ifname br0 con-name br0 ipv4.method auto || { echo "nmcli bridge setup failed"; return; }
    nmcli connection modify br0 bridge.stp no ipv6.method ignore
    nmcli connection add type bridge-slave ifname "$PRIMARY_IF" master br0 || echo "nmcli slave add failed"
    nmcli connection up br0 || echo "Please activate br0 manually in your NM tool."
    echo "Bridge br0 created; $PRIMARY_IF enslaved."
  else
    echo "NetworkManager not detected. Doing a temporary manual bridge (may interrupt networking)..."
    IP_ADDR=$(ip -4 -o addr show "$PRIMARY_IF" | awk '{print $4}')
    GATEWAY=$(ip -4 route show default | awk '/default/ {print $3}')
    ip link set "$PRIMARY_IF" down
    ip link add br0 type bridge
    ip link set "$PRIMARY_IF" master br0
    if [[ -n "${IP_ADDR:-}" ]]; then ip addr add "$IP_ADDR" dev br0 || true; fi
    ip link set br0 up
    ip link set "$PRIMARY_IF" up
    if [[ -n "${GATEWAY:-}" ]]; then ip route add default via "$GATEWAY" dev br0 || true; fi
    echo "Manual bridge br0 up. Make it persistent via your distro's network config."
  fi
}

add_user_to_groups() {
  echo "Adding user to libvirt/kvm groups..."
  local GROUP_LIBVIRT="libvirt"
  getent group libvirt >/dev/null || { getent group libvirtd >/dev/null && GROUP_LIBVIRT="libvirtd"; }
  getent group "$GROUP_LIBVIRT" >/dev/null || groupadd "$GROUP_LIBVIRT"

  local USER_TO_ADD="${SUDO_USER:-$USER}"
  if [[ -n "$USER_TO_ADD" && "$USER_TO_ADD" != "root" ]]; then
    usermod -aG "$GROUP_LIBVIRT" "$USER_TO_ADD" || true
    if getent group kvm >/dev/null; then usermod -aG kvm "$USER_TO_ADD" || true; fi
    echo "Added $USER_TO_ADD to groups: $GROUP_LIBVIRT $(getent group kvm >/dev/null && echo 'kvm')."
  else
    echo "No non-root user detected; skipping group changes."
  fi
}

enable_libvirt_service() {
  echo "Enabling and starting libvirtd..."
  systemctl enable --now libvirtd.service || true
  systemctl enable --now libvirtd.socket || true
  echo "libvirtd is enabled."
}

### main
if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)."; exit 1
fi

detect_distro
update_system
install_packages

read -rp "Do you want to set up bridged networking (y/N)? " RESP
if [[ "$RESP" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  setup_bridged_network
else
  echo "Skipping bridged networking; NAT will be used."
fi

configure_default_network
enable_libvirt_service
add_user_to_groups

echo
echo "All set. Launch 'virt-manager'."
echo "- NAT network 'default' on virbr0 is active."
echo "- If you enabled bridging, use 'br0' in your VM NIC."
echo "- Log out/in if group changes don’t take effect immediately."
