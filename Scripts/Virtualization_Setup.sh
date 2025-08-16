#!/bin/bash

# QEMU/KVM and virt-manager installation script for Debian/Ubuntu, Fedora/RHEL, and Arch Linux.
# This script must be run as root. It will install virtualization packages (QEMU, KVM, libvirt, virt-manager),
# configure default networking, and optionally set up a bridged network.

set -e  # Exit on any error

# Function to detect Linux distribution and package manager
detect_distro() {
    echo "Detecting Linux distribution..."
    # Source os-release if available for ID/ID_LIKE
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
    fi
    # Determine package manager based on distro
    case "$ID" in
        ubuntu|debian)
            PKG_MGR="apt"
            ;;
        fedora)
            PKG_MGR="dnf"
            ;;
        centos|rocky|almalinux|alma|rhel|ol)
            PKG_MGR="dnf"
            ;;
        arch|manjaro|endeavouros|arcolinux)
            PKG_MGR="pacman"
            ;;
        *)
            # Fallback: try ID_LIKE field
            if [[ "$ID_LIKE" == *"debian"* ]]; then
                PKG_MGR="apt"
            elif [[ "$ID_LIKE" == *"rhel"* ]] || [[ "$ID_LIKE" == *"fedora"* ]]; then
                PKG_MGR="dnf"
            elif [[ "$ID_LIKE" == *"arch"* ]]; then
                PKG_MGR="pacman"
            else
                echo "Unsupported distribution. Exiting."
                exit 1
            fi
            ;;
    esac
    echo "Detected package manager: $PKG_MGR"
}

# Function to update package lists (and upgrade if applicable)
update_system() {
    echo "Updating package repository information..."
    case "$PKG_MGR" in
        apt)
            apt-get update -y
            ;;  # (apt-get upgrade -y can be added if full upgrade is desired)
        dnf)
            dnf -y update
            ;;
        pacman)
            pacman -Sy --noconfirm  # refresh package index
            # For Arch, perform a full upgrade to avoid partial upgrades
            pacman -Su --noconfirm
            ;;
    esac
}

# Function to install virtualization packages
install_packages() {
    echo "Installing QEMU, KVM, libvirt, and virt-manager packages..."
    case "$PKG_MGR" in
        apt)
            # Debian/Ubuntu package names:contentReference[oaicite:4]{index=4}
            apt-get install -y qemu-kvm qemu-utils libvirt-daemon-system libvirt-clients virt-manager \
                               bridge-utils dnsmasq ebtables usbredir gir1.2-spiceclientgtk-3.0
            ;;
        dnf)
            # Fedora/RHEL package names:contentReference[oaicite:5]{index=5} (bridge-utils & ebtables may require EPEL on RHEL)
            # Enable EPEL on RHEL-based distros for extra packages like bridge-utils if not Fedora
            if [[ "$ID" =~ (centos|rocky|almalinux|alma|rhel|ol) ]]; then
                echo "Enabling EPEL repository for additional packages..."
                dnf install -y epel-release || true
            fi
            dnf install -y qemu-kvm qemu-img libvirt virt-install virt-manager bridge-utils dnsmasq ebtables usbredir spice-gtk || {
                echo "Some optional packages (SPICE/USB) may not be available on this distro."
            }
            ;;
        pacman)
            # Arch/Manjaro package names:contentReference[oaicite:6]{index=6}:contentReference[oaicite:7]{index=7}
            pacman -S --needed --noconfirm qemu-full libvirt virt-manager dnsmasq bridge-utils ebtables
            # In Arch, install optional virtualization extras
            pacman -S --needed --noconfirm spice-gtk usbredir openbsd-netcat vde2 || true
            ;;
    esac
    echo "Package installation completed."
}

# Function to configure libvirt default network (NAT)
configure_default_network() {
    echo "Configuring default libvirt network (NAT)..."
    # Ensure libvirtd is running to define/start networks
    systemctl restart libvirtd || true  # restart in case it was just installed
    # Define and start default network if not already active
    if virsh net-info default &>/dev/null; then
        # default network is defined
        if ! virsh net-list --all | grep -q default; then
            virsh net-define /usr/share/libvirt/networks/default.xml || true
        fi
        # Start and autostart default network if not already running
        virsh net-start default 2>/dev/null || true
        virsh net-autostart default 2>/dev/null || true
    else
        # On some distros, default network XML may not be present, create a basic NAT network
        echo "Defining a new default NAT network..."
        virsh net-define <(cat <<EOF
<network>
  <name>default</name>
  <uuid>$(uuidgen)</uuid>
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
        virsh net-start default || true
        virsh net-autostart default || true
    fi
    echo "Default network 'default' is active (NAT via virbr0)."
}

# Function to set up bridged networking (optional)
setup_bridged_network() {
    echo "User requested bridged networking setup."
    # Install bridge utilities if not installed (some distros might not have installed above if skipped)
    case "$PKG_MGR" in
        apt) apt-get install -y bridge-utils ;;
        dnf) dnf install -y bridge-utils || true ;;  # already attempted above
        pacman) pacman -S --needed --noconfirm bridge-utils ;;
    esac
    # Determine the primary network interface (the one with default route)
    PRIMARY_IF=$(ip -o route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++){ if($i=="dev"){print $(i+1); exit}}}')
    if [[ -z "$PRIMARY_IF" ]]; then
        echo "Could not detect primary interface for bridging. Skipping bridge setup."
        return
    fi
    echo "Primary network interface is '$PRIMARY_IF'. Configuring bridge 'br0' with this interface."
    # If NetworkManager is active, use nmcli to create a persistent bridge connection:contentReference[oaicite:8]{index=8}
    if command -v nmcli &>/dev/null && systemctl is-active --quiet NetworkManager; then
        echo "Using NetworkManager (nmcli) to set up bridge..."
        # Disconnect the interface from any active connection
        nmcli device disconnect "$PRIMARY_IF" || true
        # Add bridge and enslave the interface
        nmcli connection add type bridge ifname br0 con-name br0 ipv4.method auto || { echo "nmcli bridge setup failed"; return; }
        nmcli connection modify br0 bridge.stp no ipv6.method ignore
        nmcli connection add type bridge-slave ifname "$PRIMARY_IF" master br0 || { echo "nmcli slave setup failed"; }
        # Bring up the new bridge connection
        nmcli connection up br0 || echo "Please activate the bridge br0 manually."
        echo "Bridge 'br0' created and interface '$PRIMARY_IF' added as slave (using NetworkManager)."
        echo "NetworkManager will auto-connect 'br0' on boot.:contentReference[oaicite:9]{index=9}"
    else
        # No NetworkManager - attempt manual bridge configuration (may disrupt connectivity)
        echo "NetworkManager not available. Setting up bridge manually (temporary setup)..."
        echo "WARNING: Manual bridge setup may interrupt your network connection."
        # Save current IP and route to reapply to bridge
        IP_ADDR=$(ip -4 -o addr show "$PRIMARY_IF" | awk '{print $4}')
        GATEWAY=$(ip -4 route show default | awk '/default/ {print $3}')
        # Bring interface down and create bridge
        ip link set "$PRIMARY_IF" down
        ip link add br0 type bridge
        ip link set "$PRIMARY_IF" master br0
        # Assign IP to br0 (reuse current IP if static or DHCP lease) and bring up
        if [[ -n "$IP_ADDR" ]]; then
            ip addr add "$IP_ADDR" dev br0 || true
        fi
        ip link set br0 up
        ip link set "$PRIMARY_IF" up
        if [[ -n "$GATEWAY" ]]; then
            ip route add default via "$GATEWAY" dev br0 || true
        fi
        echo "Bridge 'br0' is set up. Please update your network configuration to make this permanent."
        echo "For a persistent bridge, consider using your distro's network configuration (Netplan, /etc/network/interfaces, etc.)."
    fi
}

# Function to add user to libvirt group for permissions:contentReference[oaicite:10]{index=10}
add_user_to_libvirt_group() {
    # Determine group name ('libvirt' is common; older systems used 'libvirtd')
    local LIBVIRT_GROUP
    if getent group libvirt >/dev/null; then
        LIBVIRT_GROUP="libvirt"
    elif getent group libvirtd >/dev/null; then
        LIBVIRT_GROUP="libvirtd"
    else
        # If group doesn't exist, create it (especially on some Arch systems)
        groupadd libvirt
        LIBVIRT_GROUP="libvirt"
    fi
    # Determine the non-root user to add (if running via sudo)
    local USER_TO_ADD="$SUDO_USER"
    if [[ -z "$USER_TO_ADD" ]]; then
        USER_TO_ADD="$USER"  # in case script is run as root directly
    fi
    if [[ -n "$USER_TO_ADD" && "$USER_TO_ADD" != "root" ]]; then
        usermod -aG "$LIBVIRT_GROUP" "$USER_TO_ADD" 
        echo "Added user '$USER_TO_ADD' to group '$LIBVIRT_GROUP' for libvirt access:contentReference[oaicite:11]{index=11}."
    else
        echo "No non-root user detected. Skipping adding to libvirt group."
    fi
}

# Function to enable and start libvirt daemon service
enable_libvirt_service() {
    echo "Enabling and starting libvirtd service..."
    systemctl enable --now libvirtd.service || true
    # On some systems, libvirtd is socket-activated; enable socket as well
    systemctl enable --now libvirtd.socket || true
    echo "libvirtd service is enabled and running:contentReference[oaicite:12]{index=12}."
}

# --- Script execution starts here ---

# 1. Ensure running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Please run again with sudo or as root."
    exit 1
fi

# 2. Detect distribution and package manager
detect_distro

# 3. Update system package index (and upgrade if applicable)
update_system

# 4. Install necessary packages
install_packages

# 5. Prompt for bridged networking setup
read -rp "Do you want to set up bridged networking (y/N)? " RESP
if [[ "$RESP" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    setup_bridged_network
else
    echo "Skipping bridged networking setup. Default NAT networking will be used."
fi

# 6. Configure libvirt default NAT network
configure_default_network

# 7. Add current user to libvirt group (for managing VMs without root)
add_user_to_libvirt_group

# 8. Enable and start libvirt service
enable_libvirt_service

echo "Installation and configuration complete. You can now launch virt-manager to create and manage VMs."
echo "If you set up a bridge, ensure your host network is configured to use 'br0'. Otherwise, the default 'virbr0' NAT network is active."
