#!/bin/bash

# ==========================================
# 1. Update gsettings
# ==========================================
SCHEMA="org.gnome.desktop.interface"
TARGET_VALUE="'manual'" 
KEY="font-rendering" # Note: Replaced with appropriate font-rendering key for this context

CURRENT_VALUE=$(gsettings get "$SCHEMA" "$KEY")

if [ "$CURRENT_VALUE" != "$TARGET_VALUE" ]; then
    echo "Current value is $CURRENT_VALUE. Updating to $TARGET_VALUE..."
    gsettings set "$SCHEMA" "$KEY" "$TARGET_VALUE"
    
    NEW_VALUE=$(gsettings get "$SCHEMA" "$KEY")
    if [ "$NEW_VALUE" == "$TARGET_VALUE" ]; then
        echo "Success: $KEY is now set to $NEW_VALUE."
    else
        echo "Error: Failed to update the setting."
    fi
else
    echo "No action needed: $KEY is already set to $TARGET_VALUE."
fi

echo "----------------------------------------"

# ==========================================
# 2. Write GTK 4.0 settings.ini
# ==========================================
GTK4_CONFIG_DIR="$HOME/.config/gtk-4.0"
SETTINGS4_FILE="$GTK4_CONFIG_DIR/settings.ini"

# Create the directory if it doesn't exist
echo "Ensuring directory $GTK4_CONFIG_DIR exists..."
mkdir -p "$GTK4_CONFIG_DIR"

# Write the contents to the file (this will overwrite the file if it exists)
echo "Writing GTK 4.0 settings to $SETTINGS4_FILE..."
cat <<EOF > "$SETTINGS4_FILE"
[Settings]
gtk-font-rendering=manual
gtk-hint-font-metrics=0
gtk-xft-hintstyle=hintnone
gtk-xft-hinting=0
gtk-application-prefer-dark-theme=0
EOF

echo "Success: GTK 4.0 settings.ini has been created/updated."

echo "----------------------------------------"

# ==========================================
# 3. Write GTK 3.0 settings.ini
# ==========================================
GTK3_CONFIG_DIR="$HOME/.config/gtk-3.0"
SETTINGS3_FILE="$GTK3_CONFIG_DIR/settings.ini"

# Create the directory if it doesn't exist
echo "Ensuring directory $GTK3_CONFIG_DIR exists..."
mkdir -p "$GTK3_CONFIG_DIR"

# Write the contents to the file (this will overwrite the file if it exists)
echo "Writing GTK 3.0 settings to $SETTINGS3_FILE..."
cat <<EOF > "$SETTINGS3_FILE"
[Settings]
gtk-xft-antialias=1
gtk-xft-rgba=none
gtk-xft-hinting=0
gtk-xft-hintstyle=hintnone
gtk-application-prefer-dark-theme=0
EOF

echo "Success: GTK 3.0 settings.ini has been created/updated."

echo "----------------------------------------"

# ==========================================
# 4. Write fontconfig fonts.conf
# ==========================================
FONT_CONFIG_DIR="$HOME/.config/fontconfig"
FONTS_CONF_FILE="$FONT_CONFIG_DIR/fonts.conf"

# Create the directory if it doesn't exist
echo "Ensuring directory $FONT_CONFIG_DIR exists..."
mkdir -p "$FONT_CONFIG_DIR"

# Write the first 5 assign commands to the fonts.conf file 
echo "Writing fontconfig settings to $FONTS_CONF_FILE..."
cat <<EOF > "$FONTS_CONF_FILE"
<?xml version='1.0'?>
<!DOCTYPE fontconfig SYSTEM 'fonts.dtd'>
<fontconfig>
  <match target="font">
    <edit name="hinting" mode="assign">
      <bool>false</bool>
    </edit>
    <edit name="autohint" mode="assign">
      <bool>false</bool>
    </edit>
    <edit name="hintstyle" mode="assign">
      <const>hintnone</const>
    </edit>
    <edit name="antialias" mode="assign">
      <bool>true</bool>
    </edit>
    <!-- Set RGBA subpixel order to none (grayscale) -->
    <edit name="rgba" mode="assign">
      <const>none</const>
    </edit>
  </match>
</fontconfig>
EOF

echo "Success: fonts.conf has been created/updated."
