#!/bin/bash

# Get the current username and home directory
USER_NAME=$(whoami)
USER_HOME=$HOME

echo "--- Audio Configuration Installer ---"
echo "Targeting user: $USER_NAME"
echo "Targeting home: $USER_HOME"
echo "-------------------------------------"

# Function to copy files and create directories
install_file() {
    local src=$1
    local dest=$2

    if [ -f "$src" ]; then
        echo "Installing $src to $dest..."
        mkdir -p "$(dirname "$dest")"
        cp "$src" "$dest"
    else
        echo "Warning: Source file '$src' not found in current directory. Skipping."
    fi
}

# 1. User-level PipeWire Configs
install_file "iMacAudio.conf" "$USER_HOME/.config/pipewire/pipewire.conf.d/iMacAudio.conf"

# 2. System-level IRS files (Requires sudo)
IRS_DIR="/usr/share/imac-audio"
echo "Preparing to install system-level IRS files..."

# Create the destination directory if it doesn't exist
sudo mkdir -p "$IRS_DIR"

# Loop through and install all necessary IRS files
for irs_file in "Filters L Aug 14-MP.wav" "Filters R Aug 14-MP.wav" "Filters C2 Aug 16-MP.wav" "Filters LFE Aug 16-MP.wav"; do
    if [ -f "$irs_file" ]; then
        echo "Installing $irs_file to $IRS_DIR/$irs_file..."
        sudo cp "$irs_file" "$IRS_DIR/$irs_file"
    else
        echo "Warning: Source file '$irs_file' not found in current directory. Skipping."
    fi
done

# 3. Model detection and configuration
REBOOT_NEEDED=0
PRODUCT_NAME=$(cat /sys/class/dmi/id/product_name 2>/dev/null || sudo dmidecode -s system-product-name 2>/dev/null || echo "")

if [ "$PRODUCT_NAME" = "iMac17,1" ]; then
    echo "Detected target model: $PRODUCT_NAME"
    MODPROBE_FILE="/etc/modprobe.d/imac_local.conf"
    MODPROBE_LINE="options snd-hda-intel model=imac27"

    if [ -f "$MODPROBE_FILE" ] && grep -Fxq "$MODPROBE_LINE" "$MODPROBE_FILE"; then
        echo "ALSA option already present in $MODPROBE_FILE. Skipping addition."
    else
        echo "Adding snd-hda-intel model option to $MODPROBE_FILE..."
        echo "$MODPROBE_LINE" | sudo tee -a "$MODPROBE_FILE" > /dev/null
        REBOOT_NEEDED=1
    fi
# 5K iMac models released after 17,1: iMac18,3 (2017), iMac19,1 (2019), iMac20,1 / iMac20,2 (2020)
elif [[ "$PRODUCT_NAME" =~ ^iMac(18,3|19,1|20,1|20,2)$ ]]; then
    echo "----------------------------------------------------------------------"
    echo "NOTICE: Detected 5K iMac newer than 17,1 ($PRODUCT_NAME)."
    echo "Please ensure you have installed the custom audio driver from:"
    echo "https://github.com/davidjo/snd_hda_macbookpro"
    echo "----------------------------------------------------------------------"
fi

echo "-------------------------------------"
echo "Installation complete!"

if [ "$REBOOT_NEEDED" -eq 1 ]; then
    echo ""
    echo "Kernel audio parameters were modified for your iMac ($PRODUCT_NAME)."
    read -rp "A reboot is required for these settings to apply. Reboot now? [y/N]: " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        echo "Rebooting system..."
        sudo reboot
    else
        echo "Please remember to restart your computer manually later."
    fi
else
    echo "To apply changes, restart PipeWire and WirePlumber using:"
    echo "systemctl --user restart pipewire wireplumber"
fi
