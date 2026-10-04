#!/bin/bash

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root: sudo ./iMac5K-GRUBFontSize.sh"
  exit 1
fi

echo "1. Checking for Unifont source file..."
# Dynamically search for the font file (handles both .ttf and .otf)
FONT_SOURCE=$(find /usr/share/fonts -type f -iname "unifont.*tf" | grep -v "upper" | grep -v "csur" | head -n 1)

if [ -z "$FONT_SOURCE" ]; then
    echo "   unifont file not found. Installing fonts-unifont..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y fonts-unifont
    # Search again after installation
    FONT_SOURCE=$(find /usr/share/fonts -type f -iname "unifont.*tf" | grep -v "upper" | grep -v "csur" | head -n 1)
fi

# Double check that we actually found it this time
if [ -z "$FONT_SOURCE" ] || [ ! -f "$FONT_SOURCE" ]; then
    echo "Error: Failed to install or locate the Unifont file in /usr/share/fonts."
    exit 1
fi

echo "   Found Unifont source at: $FONT_SOURCE"

FONT_DEST="/boot/grub/fonts/unicode32.pf2"
FONT_SIZE=32

echo "2. Compiling new GRUB font (Size: $FONT_SIZE) from Unifont..."
# Note: "unsupported font feature parameters: a" warning is expected and harmless
grub-mkfont -s $FONT_SIZE -o "$FONT_DEST" "$FONT_SOURCE"

if [ ! -f "$FONT_DEST" ]; then
    echo "Error: Failed to create the .pf2 font file."
    exit 1
fi

echo "3. Updating /etc/default/grub..."
GRUB_CFG="/etc/default/grub"

# Check if GRUB_FONT is already defined
if grep -q "^GRUB_FONT=" "$GRUB_CFG"; then
    sed -i "s|^GRUB_FONT=.*|GRUB_FONT=\"$FONT_DEST\"|" "$GRUB_CFG"
else
    echo "" >> "$GRUB_CFG"
    echo "# Custom Large GRUB Font" >> "$GRUB_CFG"
    echo "GRUB_FONT=\"$FONT_DEST\"" >> "$GRUB_CFG"
fi

echo "4. Applying changes to GRUB..."
update-grub

echo "5. Configuring Linux TTY console font to maximum size (Terminus 16x32)..."
CONSOLE_CFG="/etc/default/console-setup"

# Install terminus fonts package if not present
if ! dpkg -s fonts-terminus >/dev/null 2>&1; then
    echo "   Installing fonts-terminus and console-setup..."
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y fonts-terminus console-setup
fi

# Backup console-setup if not already backed up
if [ -f "$CONSOLE_CFG" ] && [ ! -f "${CONSOLE_CFG}.bak" ]; then
    cp "$CONSOLE_CFG" "${CONSOLE_CFG}.bak"
fi

# Configure console settings for largest standard TTY font
set_or_append() {
    local key="$1"
    local val="$2"
    local file="$3"
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=\"${val}\"|" "$file"
    else
        echo "${key}=\"${val}\"" >> "$file"
    fi
}

set_or_append "FONTFACE" "Terminus" "$CONSOLE_CFG"
set_or_append "FONTSIZE" "16x32" "$CONSOLE_CFG"
set_or_append "CODESET" "guess" "$CONSOLE_CFG"

echo "6. Applying font to active console and updating initramfs..."
# Apply font to active virtual terminal immediately if running inside a TTY
if [ -c /dev/tty0 ]; then
    setupcon --save-only 2>/dev/null || true
    setfont /usr/share/consolefonts/Uni3-Terminus32x16.psf.gz 2>/dev/null || true
fi

# Update initramfs so font applies on early boot
update-initramfs -u

echo "Done! GRUB and TTY fonts have been updated. Reboot your system to see all changes."
