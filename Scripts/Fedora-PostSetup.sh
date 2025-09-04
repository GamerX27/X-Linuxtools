#!/bin/bash
set -euo pipefail

echo "=== Updating system ==="
sudo dnf -y update

echo "=== Installing RPM Fusion Free and Nonfree repositories ==="
sudo dnf -y install \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

echo "=== Updating @core group after enabling RPM Fusion ==="
sudo dnf -y update @core

echo "=== Swapping ffmpeg-free with full ffmpeg ==="
sudo dnf -y swap ffmpeg-free ffmpeg --allowerasing

echo "=== Updating @multimedia group (without weak deps, excluding PackageKit-gstreamer-plugin) ==="
sudo dnf -y update @multimedia \
  --setopt="install_weak_deps=False" \
  --exclude=PackageKit-gstreamer-plugin

echo "=== GPU / Media driver setup ==="
echo "Select your option:"
echo "  1) Intel (recent GPUs: Broadwell and newer)"
echo "  2) Intel (older GPUs: pre-Broadwell)"
echo "  3) AMD GPUs (Freeworld drivers)"

read -rp "Enter 1, 2, or 3: " choice

case "$choice" in
    1)
        echo "Installing intel-media-driver (new Intel)..."
        sudo dnf -y install intel-media-driver
        ;;
    2)
        echo "Installing libva-intel-driver (old Intel)..."
        sudo dnf -y install libva-intel-driver
        ;;
    3)
        echo "Swapping to AMD Freeworld VAAPI/VDPAU drivers..."
        sudo dnf -y swap mesa-va-drivers mesa-va-drivers-freeworld
        sudo dnf -y swap mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
        sudo dnf -y swap mesa-va-drivers.i686 mesa-va-drivers-freeworld.i686
        sudo dnf -y swap mesa-vdpau-drivers.i686 mesa-vdpau-drivers-freeworld.i686
        ;;
    *)
        echo "Invalid choice. Skipping GPU/media driver installation."
        ;;
esac

echo "=== All done ✅ ==="
