#!/usr/bin/env bash

# Prompt function
ask_install() {
    local app_name="$1"
    local flatpak_id="$2"
    while true; do
        read -p "Install ${app_name}? (y/n): " answer
        case "${answer,,}" in
            y|yes)
                echo "Installing ${app_name}..."
                flatpak install flathub "${flatpak_id}" -y
                break
                ;;
            n|no)
                echo "Skipping ${app_name}."
                break
                ;;
            *)
                echo "Please answer 'y' or 'n'."
                ;;
        esac
    done
    echo
}

echo "=== Installing extras ==="

# Ensure Flathub is enabled
if ! flatpak remotes | grep -q "^flathub"; then
    echo "Adding Flathub repository..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    echo
fi

# Installation prompts for extras
ask_install "Cryptomator" "org.cryptomator.Cryptomator"
ask_install "Bitwarden" "com.bitwarden.desktop"
ask_install "LocalSend" "org.localsend.localsend_app"
ask_install "Syncthing" "com.syncthing.Syncthing"

echo "=== Extras processing complete ==="
