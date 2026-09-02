#!/usr/bin/env bash
set -euo pipefail

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (e.g., using sudo)." >&2
    exit 1
fi

GRUB_FILE="/etc/default/grub"
BACKUP_FILE="/etc/default/grub.bak.$(date +%Y%m%d%H%M%S)"
FLAGS=("amdgpu.ppfeaturemask=0xfff7bbff" "reboot=pci" "acpi_backlight=native")

if [[ ! -f "$GRUB_FILE" ]]; then
    echo "Error: $GRUB_FILE not found." >&2
    exit 1
fi

# Create a timestamped backup
cp "$GRUB_FILE" "$BACKUP_FILE"
echo "Backup created at: $BACKUP_FILE"

# Extract the existing GRUB_CMDLINE_LINUX_DEFAULT value
CURRENT_CMDLINE=$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE" | sed -E 's/^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"/\1/' || true)

# If the line doesn't exist, append it cleanly
if [[ -z "${CURRENT_CMDLINE+x}" ]] || ! grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE"; then
    NEW_CMDLINE="${FLAGS[*]}"
    echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_CMDLINE\"" >> "$GRUB_FILE"
else
    NEW_CMDLINE="$CURRENT_CMDLINE"
    for flag in "${FLAGS[@]}"; do
        # Check if the flag (or its key before '=') is already present
        FLAG_KEY="${flag%%=*}"
        if echo "$NEW_CMDLINE" | grep -qw "$FLAG_KEY"; then
            echo "Skipping '$flag': a parameter matching '$FLAG_KEY' is already present."
        else
            NEW_CMDLINE="$(echo -e "${NEW_CMDLINE} ${flag}" | sed -e 's/^[[:space:]]*//')"
            echo "Added: $flag"
        fi
    done

    # Replace the existing line in /etc/default/grub
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_CMDLINE\"|" "$GRUB_FILE"
fi

echo "Updated line: GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_CMDLINE\""

# Regenerate GRUB configuration
echo "Regenerating GRUB configuration..."
update-grub

echo "Done! Reboot your system for the kernel parameters to take effect."
