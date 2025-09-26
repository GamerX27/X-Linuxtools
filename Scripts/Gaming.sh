#!/usr/bin/env bash
set -euo pipefail

# Gaming stack installer (Steam via package manager; Lutris/Heroic per your rules)
# - Debian-based: Steam (apt), Wine/Winetricks/MangoHud/GameMode/Vulkan (apt),
#                 Lutris (Flatpak), Heroic (Flatpak)
# - Fedora-based: Steam (dnf), Wine/Winetricks/MangoHud/GameMode/Vulkan (dnf),
#                 Lutris (dnf), Heroic (Flatpak)
# - Arch-based:   Steam (pacman), Wine/Winetricks/MangoHud/GameMode/Vulkan (pacman),
#                 Lutris (pacman), Heroic (AUR via yay)
#
# Run with sudo: sudo ./gaming-setup.sh

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Please run as root (e.g., sudo $0)"
    exit 1
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_flatpak_and_flathub() {
  if ! have_cmd flatpak; then
    echo "[*] Installing Flatpak…"
    if have_cmd dnf; then
      dnf install -y flatpak
    elif have_cmd apt; then
      apt update
      apt install -y flatpak
    elif have_cmd pacman; then
      pacman -Syu --noconfirm flatpak
    else
      echo "[-] Could not install Flatpak on this system."
      return 1
    fi
  fi
  if ! flatpak remote-list | awk '{print $1}' | grep -q '^flathub$'; then
    echo "[*] Adding Flathub…"
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi
}

install_mangohud_gamemode() {
  echo "[*] Installing MangoHud + GameMode…"
  if have_cmd dnf; then
    dnf install -y mangohud gamemode
  elif have_cmd apt; then
    apt update
    apt install -y mangohud gamemode
    # Optional 32-bit MangoHud if multiarch enabled
    dpkg --print-foreign-architectures | grep -q '^i386$' && apt install -y mangohud:i386 || true
  elif have_cmd pacman; then
    pacman -S --noconfirm mangohud gamemode
  fi
}

########## Debian / Ubuntu family ##########
install_debian_like() {
  echo "[*] Debian/Ubuntu family detected."

  # Enable i386 for Steam/Wine 32-bit libs
  if ! dpkg --print-foreign-architectures | grep -q '^i386$'; then
    echo "[*] Enabling i386 multiarch…"
    dpkg --add-architecture i386
  fi
  apt update

  echo "[*] Installing Steam (apt)…"
  if apt-cache policy steam-installer 2>/dev/null | grep -q Candidate; then
    apt install -y steam-installer
  elif apt-cache policy steam 2>/dev/null | grep -q Candidate; then
    apt install -y steam
  else
    echo "[-] Steam package not found in your current repos."
    echo "    On Debian/Ubuntu you may need to enable non-free/multiverse."
    echo "    Aborting Steam install (per requirement: no Flatpak fallback)."
  fi

  echo "[*] Installing Wine + Winetricks…"
  apt install -y wine winetricks

  echo "[*] Installing Vulkan drivers (64-bit + 32-bit)…"
  apt install -y mesa-vulkan-drivers mesa-vulkan-drivers:i386 || true

  install_mangohud_gamemode

  echo "[*] Installing Lutris (Flatpak) + Heroic (Flatpak)…"
  ensure_flatpak_and_flathub
  flatpak install -y flathub net.lutris.Lutris
  flatpak install -y flathub com.heroicgameslauncher.hgl
}

########## Fedora / RHEL family ##########
enable_rpmfusion_fedora() {
  echo "[*] Enabling RPM Fusion (free + nonfree) for Fedora…"
  dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
}

install_fedora_like() {
  echo "[*] Fedora/RHEL family detected."

  # Steam lives in RPM Fusion on Fedora proper
  if [ "${ID:-}" = "fedora" ]; then
    enable_rpmfusion_fedora
  else
    echo "[i] On ${PRETTY_NAME:-this system}, Steam may require enabling appropriate repos (e.g., RPM Fusion for EL)."
    echo "    Proceeding to install; if it fails, enable the needed repos and re-run."
  fi

  echo "[*] Installing Steam (dnf)…"
  dnf install -y steam || echo "[-] Steam install failed. Enable RPM Fusion/EL repos and re-run."

  echo "[*] Installing Wine + Winetricks…"
  dnf install -y wine winetricks

  echo "[*] Installing Vulkan drivers (64-bit + 32-bit)…"
  dnf install -y mesa-vulkan-drivers vulkan-loader || true
  dnf install -y mesa-vulkan-drivers.i686 vulkan-loader.i686 || true

  install_mangohud_gamemode

  echo "[*] Installing Lutris (dnf)…"
  dnf install -y lutris

  echo "[*] Installing Heroic (Flatpak)…"
  ensure_flatpak_and_flathub
  flatpak install -y flathub com.heroicgameslauncher.hgl
}

########## Arch / Manjaro / EndeavourOS ##########
enable_arch_multilib() {
  if ! grep -Eq '^\[multilib\]' /etc/pacman.conf; then
    if grep -Eq '^\s*#\s*\[multilib\]' /etc/pacman.conf; then
      echo "[*] Enabling multilib repo in /etc/pacman.conf…"
      sed -i "/\[multilib\]/,/Include/s/^#//" /etc/pacman.conf
    fi
  fi
}

ensure_yay() {
  if have_cmd yay; then return 0; fi
  echo "[*] yay not found—installing from AUR…"
  pacman -Syu --needed --noconfirm git base-devel
  USERNAME="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
  sudo -u "$USERNAME" bash -c '
    set -e
    cd "$HOME"
    [ -d yay ] || git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
  '
}

install_arch_like() {
  echo "[*] Arch/Arch-based detected."
  enable_arch_multilib
  pacman -Syu --noconfirm

  echo "[*] Installing Steam (pacman)…"
  pacman -S --noconfirm steam

  echo "[*] Installing Wine + Winetricks…"
  pacman -S --noconfirm wine winetricks

  echo "[*] Installing Vulkan loader (64-bit + 32-bit)…"
  pacman -S --noconfirm vulkan-icd-loader lib32-vulkan-icd-loader

  echo "[*] Installing Lutris (pacman)…"
  pacman -S --noconfirm lutris

  install_mangohud_gamemode

  echo "[*] Installing Heroic (AUR via yay)…"
  ensure_yay
  USERNAME="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
  sudo -u "$USERNAME" yay -S --noconfirm heroic-games-launcher-bin
}

########## Entry point ##########
main() {
  require_root
  [ -r /etc/os-release ] || { echo "Cannot detect distro (no /etc/os-release)."; exit 1; }
  . /etc/os-release
  id_like=$(echo "${ID_LIKE:-}" | tr '[:upper:]' '[:lower:]')
  id=$(echo "${ID:-}" | tr '[:upper:]' '[:lower:]')

  if echo "$id $id_like" | grep -Eq 'debian|ubuntu|linuxmint|pop|elementary|mx|zorin|kali|raspbian'; then
    install_debian_like
  elif echo "$id $id_like" | grep -Eq 'fedora|rhel|centos|nobara|rocky|alma'; then
    install_fedora_like
  elif echo "$id $id_like" | grep -Eq 'arch|manjaro|endeavouros|garuda|arco|rebornos'; then
    install_arch_like
  else
    echo "Unsupported or unrecognized distro: ${PRETTY_NAME:-unknown}"
    echo "Targets: Debian-based, Fedora-based, and Arch-based."
    exit 2
  fi

  echo
  echo "[✓] Done. Reboot recommended."
  echo "Tips:"
  echo " - In Steam: enable Steam Play/Proton for all titles (Settings → Compatibility)."
  echo " - MangoHud: use launch option 'MANGOHUD=1 %command%'."
  echo " - GameMode: use launch option 'gamemoderun %command%'."
}

main "$@"
