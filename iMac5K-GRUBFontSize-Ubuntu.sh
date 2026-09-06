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
    # Replace existing line
    sed -i "s|^GRUB_FONT=.*|GRUB_FONT=\"$FONT_DEST\"|" "$GRUB_CFG"
else
    # Append to the end
    echo "" >> "$GRUB_CFG"
    echo "# Custom Large GRUB Font" >> "$GRUB_CFG"
    echo "GRUB_FONT=\"$FONT_DEST\"" >> "$GRUB_CFG"
fi

echo "4. Applying changes to GRUB..."
update-grub

echo "Done! The new font size is ~$(du -h $FONT_DEST | cut -f1). Reboot your system to see the changes."
