#!/bin/bash
set -euo pipefail

sudo dnf -y update

sudo dnf -y install \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

sudo dnf -y update @core

curl -fsS https://dl.brave.com/install.sh | sh

sudo dnf -y swap ffmpeg-free ffmpeg --allowerasing

sudo dnf -y update @multimedia \
  --setopt="install_weak_deps=False" \
  --exclude=PackageKit-gstreamer-plugin

echo "Select your option:"
echo "  1) Intel (recent GPUs)"
echo "  2) Intel (older GPUs)"
echo "  3) AMD GPUs"
echo "  4) VM / Skip GPU driver setup"

read -rp "Enter 1, 2, 3, or 4: " choice
case "$choice" in
    1) sudo dnf -y install intel-media-driver ;;
    2) sudo dnf -y install libva-intel-driver ;;
    3)
        sudo dnf -y swap mesa-va-drivers mesa-va-drivers-freeworld
        sudo dnf -y swap mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
        sudo dnf -y swap mesa-va-drivers.i686 mesa-va-drivers-freeworld.i686
        sudo dnf -y swap mesa-vdpau-drivers.i686 mesa-vdpau-drivers-freeworld.i686
        ;;
    4) echo "Skipping GPU/media driver installation (VM/Skip selected)" ;;
    *) echo "Invalid choice. Skipping GPU/media driver installation." ;;
esac

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

sudo dnf remove libreoffice\* dragon juk elisa

sudo dnf -y install fish papirus-icon-theme vlc fastfetch


#!/usr/bin/env bash

# All-or-nothing installer for extras
read -p "Install all extras (Cryptomator, Bitwarden, LocalSend, Syncthing)? (y/n): " answer
case "${answer,,}" in
    y|yes)
        echo "Installing all extras..."
        # Ensure Flathub is added
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

        # Install everything in one go
        flatpak install -y flathub \
            org.cryptomator.Cryptomator \
            com.bitwarden.desktop \
            org.localsend.localsend_app \
            com.github.zocker_160.SyncThingy

        echo "All extras installed."
        ;;
    *)
        echo "Skipping extras."
        ;;
esac



echo "=== Setup complete ✅ ==="
