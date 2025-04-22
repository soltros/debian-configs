#!/bin/bash

set -e

USER_HOME="/home/$USER"
FISH_CONFIG_DIR="$USER_HOME/.config/fish"
FISH_CONFIG_FILE="$FISH_CONFIG_DIR/config.fish"

# Fish shell setup
fish_setup() {
    echo "Setting up Fish config..."

    mkdir -p "$FISH_CONFIG_DIR"

    cat <<EOF > "$FISH_CONFIG_FILE"
# No greeting
set -g fish_greeting ""

# Prompt Configuration
function fish_prompt
    set_color white; echo -n (whoami)
    set_color normal; echo -n ':'
    set_color cyan; echo -n (pwd)
    set_color normal; echo -n ' '
end

# Environment Variables
export PATH="\$PATH:$USER_HOME/.local/bin"

# Aliases
alias lsblk="lsblk -e7"
EOF

    chsh -s "$(which fish)" "$USER"
    echo "Fish shell set as default for user: $USER"
}

# Add third-party repos
prepare_repos() {
    echo "Adding necessary third-party repositories..."

    if ! command -v tailscale >/dev/null 2>&1; then
        echo "Adding Tailscale repo (Trixie)..."
        curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
        curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.list | \
            sed 's/^deb /deb [signed-by=\/usr\/share\/keyrings\/tailscale-archive-keyring.gpg] /' | \
            sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null
    fi

    if ! command -v docker >/dev/null 2>&1; then
        echo "Adding Docker repo..."
        sudo apt install -y ca-certificates curl gnupg

        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg | \
            sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
          https://download.docker.com/linux/debian trixie stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    fi

    if ! command -v distrobox >/dev/null 2>&1; then
        echo "Installing Distrobox manually..."
        curl -s https://raw.githubusercontent.com/89luca89/distrobox/main/install | sudo bash
    fi
}

# APT-based package installation
install_packages() {
    echo "Removing Firefox variants..."
    sudo apt purge -y firefox firefox-esr || true
    sudo apt autoremove --purge -y

    echo "Installing APT packages..."

    sudo apt update

    sudo apt install -y \
        gimp tailscale vlc nano thunderbird git papirus-icon-theme \
        geany wine fish util-linux pciutils hwdata usbutils coreutils binutils \
        findutils grep iproute2 bash bash-completion udisks2 build-essential \
        cmake extra-cmake-modules docker-ce docker-ce-cli containerd.io
}

# Flatpak apps + Flatseal
install_flatpaks() {
    echo "Installing Flatpak and configuring Flathub..."

    sudo apt install -y flatpak

    flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

    flatpak install -y --user \
        com.mattjakeman.ExtensionManager \
        com.discordapp.Discord \
        io.kopia.KopiaUI \
        com.spotify.Client \
        com.valvesoftware.Steam \
        org.telegram.desktop \
        tv.plex.PlexDesktop \
        com.nextcloud.desktopclient.nextcloud \
        im.riot.Riot \
        com.github.tchx84.Flatseal
}

# Install VirtualBox .run file and fix module build
install_virtualbox() {
    echo "Installing kernel headers and DKMS for VirtualBox modules..."
    sudo apt install -y dkms linux-headers-amd64

    echo "Downloading VirtualBox .run installer..."
    VBOX_URL="https://download.virtualbox.org/virtualbox/7.1.8/VirtualBox-7.1.8-168469-Linux_amd64.run"
    VBOX_FILE="/tmp/VirtualBox-7.1.8.run"

    curl -L "$VBOX_URL" -o "$VBOX_FILE"
    chmod +x "$VBOX_FILE"

    echo "Running VirtualBox installer as root..."
    sudo "$VBOX_FILE"

    echo "Configuring VirtualBox kernel modules..."
    sudo /sbin/vboxconfig
}

# Install Waterfox from archive in ~/Downloads
install_waterfox() {
    echo "Installing Waterfox from archive..."

    DOWNLOADS_DIR="$HOME/Downloads"
    INSTALL_DIR="/opt/waterfox"
    BIN_LINK="/usr/local/bin/waterfox"
    DESKTOP_FILE="/usr/share/applications/waterfox.desktop"

    ARCHIVE=$(find "$DOWNLOADS_DIR" -maxdepth 1 -type f -iname "waterfox*.tar.*" | head -n 1)

    if [ -z "$ARCHIVE" ]; then
        echo "No Waterfox archive found in $DOWNLOADS_DIR."
        return 1
    fi

    echo "Found archive: $ARCHIVE"
    echo "Installing to: $INSTALL_DIR"

    sudo rm -rf "$INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR"
    sudo tar -xf "$ARCHIVE" -C "$INSTALL_DIR" --strip-components=1
    sudo ln -sf "$INSTALL_DIR/waterfox" "$BIN_LINK"

    echo "Creating desktop entry..."
    sudo tee "$DESKTOP_FILE" > /dev/null <<EOF
[Desktop Entry]
Name=Waterfox
Exec=$BIN_LINK %u
Icon=$INSTALL_DIR/browser/chrome/icons/default/default128.png
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;application/xml;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
EOF

    sudo chmod +x "$DESKTOP_FILE"
    echo "Waterfox installed successfully!"
}

# Switch between GNOME and KDE
switch_desktop_environment() {
    echo "Checking current desktop environment..."

    installed_kde=$(dpkg -l | grep -q task-kde-desktop && echo yes || echo no)
    installed_gnome=$(dpkg -l | grep -q task-gnome-desktop && echo yes || echo no)

    echo "Current status:"
    echo "  KDE installed: $installed_kde"
    echo "  GNOME installed: $installed_gnome"
    echo

    echo "Which desktop environment do you want to switch to?"
    echo "1) GNOME"
    echo "2) KDE"
    echo -n "Enter your choice: "
    read -r de_choice

    case "$de_choice" in
        1)
            echo "Switching to GNOME..."
            [ "$installed_kde" = "yes" ] && sudo apt purge -y task-kde-desktop kde-standard kde-plasma-desktop kde-full && sudo apt autoremove --purge -y
            sudo apt install -y task-gnome-desktop
            ;;
        2)
            echo "Switching to KDE..."
            [ "$installed_gnome" = "yes" ] && sudo apt purge -y task-gnome-desktop gnome-core gnome-shell gnome-session && sudo apt autoremove --purge -y
            sudo apt install -y task-kde-desktop
            ;;
        *)
            echo "Invalid choice. Aborting."
            return
            ;;
    esac

    echo "Done. You may want to reboot to fully switch desktop environments."
}

# Menu
main_menu() {
    echo "Debian Installer Menu"
    echo "1) Setup Fish shell and config"
    echo "2) Install desktop packages (APT apps, Docker, Distrobox, remove Firefox)"
    echo "3) Install Flatpak apps (Flathub + your apps)"
    echo "4) Install VirtualBox 7.1.8 (.run installer)"
    echo "5) Switch between KDE or GNOME cleanly"
    echo "6) Install Waterfox (from archive in Downloads)"
    echo "7) Quit"
    echo -n "Choose an option: "
    read -r choice

    case "$choice" in
        1) fish_setup ;;
        2) prepare_repos && install_packages ;;
        3) install_flatpaks ;;
        4) install_virtualbox ;;
        5) switch_desktop_environment ;;
        6) install_waterfox ;;
        7) echo "Bye!"; exit 0 ;;
        *) echo "Invalid option"; exit 1 ;;
    esac
}

main_menu
