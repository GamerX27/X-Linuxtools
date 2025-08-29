#!/bin/bash
# Exit immediately on error
set -e

export DEBIAN_FRONTEND=noninteractive

echo "Updating package list..."
apt update

echo "Installing curl..."
apt install -y curl

echo "Adding Brave Browser repository..."
curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources https://brave-browser-apt-release.s3.brave.com/brave-browser.sources

echo "Updating package list (Brave included)..."
apt update

echo "Installing Brave Browser..."
apt install -y brave-browser

echo "Installing KDE Standard..."
apt install -y kde-standard

echo "Installing Flatpak and Discover Flatpak Backend..."
apt install -y flatpak plasma-discover-backend-flatpak

echo "Installing fish, fastfetch, papirus theme and VLC..."
apt install -y fish fastfetch vlc papirus-icon-theme

echo "Adding Flathub repository (if not already added)..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

echo "Checking for firefox-esr..."
if dpkg -l | grep -q "^ii  firefox-esr "; then
    echo "firefox-esr is installed. Removing..."
    apt purge -y firefox-esr
    apt autoremove -y
else
    echo "firefox-esr not found. Skipping removal."
fi

echo "Cleaning up APT..."
apt autoremove -y
apt clean

# --- Optional Boot screen setup (Breeze theme) ---
read -p "Do you want to enable the Breeze boot splash screen? [y/N]: " enable_splash
if [[ "$enable_splash" =~ ^[Yy]$ ]]; then
    echo "Installing Plymouth and Breeze theme..."
    apt install -y plymouth plymouth-themes
    apt install -y plymouth-theme-breeze kde-config-plymouth

    echo "Ensuring GRUB has 'quiet splash'..."
    if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub; then
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' /etc/default/grub
    else
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' >> /etc/default/grub
    fi

    echo "Updating GRUB..."
    update-grub2

    echo "Setting Breeze theme for Plymouth..."
    plymouth-set-default-theme -R breeze

    echo "Breeze boot splash enabled."
else
    echo "Skipping boot splash setup."
fi
# ---------------------------------------------------

# --- Optional: Convert to Debian Sid before reboot ---
read -p "Do you want to convert this install to Debian Sid (rolling)? [y/N]: " to_sid
if [[ "$to_sid" =~ ^[Yy]$ ]]; then
    echo "Downloading and running Debian Sid conversion script..."
    tmp_sid_script="$(mktemp -p /tmp Deb-Sid.XXXXXX.sh)"
    wget -O "$tmp_sid_script" "https://raw.githubusercontent.com/GamerX27/X-Linuxtools/refs/heads/main/Scripts/Deb-Sid.sh"
    chmod +x "$tmp_sid_script"
    bash "$tmp_sid_script"
    echo "Debian Sid conversion script finished."
else
    echo "Skipping Debian Sid conversion."
fi
# -----------------------------------------------------

# Countdown before reboot
echo "Removing /etc/network/interfaces..."
sleep 2
rm -f /etc/network/interfaces

echo "Rebooting in:"
for i in 3 2 1; do
    echo "$i..."
    sleep 1
done

reboot
