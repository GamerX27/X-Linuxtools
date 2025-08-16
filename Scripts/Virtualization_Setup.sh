#!/bin/bash
# QEMU/KVM + virt-manager installer for apt/dnf/pacman
# NAT networking only (no bridged setup)
# Adds current user to libvirt & kvm groups
# Debian fix: disable system dnsmasq to avoid libvirt conflicts

set -euo pipefail

detect_distro() {
  echo "Detecting Linux distribution..."
  if [[ -f /etc/os-release ]]; then . /etc/os-release; fi
  case "${ID:-unknown}" in
    ubuntu|debian) PKG_MGR="apt" ;;
    fedora)        PKG_MGR="dnf" ;;
    centos|rocky|almalinux|alma|rhel|ol) PKG_MGR="dnf" ;;
    arch|manjaro|endeavouros|arcolinux)  PKG_MGR="pacman" ;;
    *)
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
      apt-get install -y \
        qemu-kvm qemu-utils libvirt-daemon-system libvirt-clients virt-manager \
        bridge-utils dnsmasq ebtables
      ;;
    dnf)
      if [[ "${ID:-}" =~ (centos|rocky|almalinux|alma|rhel|ol) ]]; then
        dnf install -y epel-release || true
      fi
      dnf install -y qemu-kvm qemu-img libvirt virt-install virt-manager \
        bridge-utils dnsmasq ebtables || true
      ;;
    pacman)
      pacman -S --needed --noconfirm qemu-full libvirt virt-manager dnsmasq bridge-utils ebtables
      ;;
  esac
  echo "Package installation completed."
}

configure_default_network() {
  echo "Configuring default libvirt NAT network..."

  # Debian/Ubuntu-specific fix: disable system dnsmasq to avoid conflicts
  if [[ "$PKG_MGR" == "apt" ]]; then
    echo "Applying Debian/Ubuntu dnsmasq fix..."
    systemctl stop dnsmasq || true
    systemctl disable dnsmasq || true
  fi

  systemctl restart libvirtd || true
  if ! virsh net-info default &>/dev/null; then
    if [[ -f /usr/share/libvirt/networks/default.xml ]]; then
      virsh net-define /usr/share/libvirt/networks/default.xml || true
    else
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
configure_default_network
enable_libvirt_service
add_user_to_groups

echo
echo "All set. Launch 'virt-manager'."
echo "- NAT network 'default' on virbr0 is active."
echo "- Log out/in if group changes don’t take effect immediately."
