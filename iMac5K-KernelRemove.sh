#!/bin/bash
set -e

# Detect OS-specific suffix matching the install script
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        linuxmint)
            OS_SUFFIX="-mint-imac5k"
            ;;
        ubuntu)
            OS_SUFFIX="-ubuntu-imac5k"
            ;;
        *)
            if [[ "$ID_LIKE" =~ "ubuntu" ]]; then
                OS_SUFFIX="-ubuntu-imac5k"
            elif [[ "$ID" = "debian" || "$ID_LIKE" =~ "debian" ]]; then
                OS_SUFFIX="-imac5k"
            else
                OS_SUFFIX="-imac5k"
            fi
            ;;
    esac
else
    echo "Warning: /etc/os-release not found. Falling back to default suffix '-imac5k'."
    OS_SUFFIX="-imac5k"
fi

echo "================================================================================"
echo "                   Custom Kernel Uninstaller"
echo "================================================================================"
echo "Currently running kernel: $(uname -r)"
echo "Detected OS suffix:       ${OS_SUFFIX}"
echo ""

# Scan for installed custom kernels matching the suffix
echo "Scanning for installed iMac 5K kernels..."
INSTALLED_KERNELS=($(find /boot -maxdepth 1 -name "vmlinuz-*${OS_SUFFIX}*" -exec basename {} \; 2>/dev/null | sed "s/^vmlinuz-//" | sort -u))

if [ ${#INSTALLED_KERNELS[@]} -gt 0 ]; then
    echo "Found custom kernels installed:"
    for k in "${INSTALLED_KERNELS[@]}"; do
        echo "  - $k"
    done
    echo ""
else
    echo "No kernels matching '${OS_SUFFIX}' found in /boot."
    echo ""
fi

# Prompt for the target kernel version
echo "Enter the base version (e.g. 7.3-rc1 or 7.2.3) or the full kernel release string:"
read -p "Kernel to uninstall: " INPUT_VERSION

if [ -z "$INPUT_VERSION" ]; then
    echo "Error: No version provided. Aborting."
    exit 1
fi

# If the user omitted the OS suffix, append it automatically
if [[ "$INPUT_VERSION" != *"${OS_SUFFIX}"* ]]; then
    TARGET_RELEASE="${INPUT_VERSION}${OS_SUFFIX}"
else
    TARGET_RELEASE="${INPUT_VERSION}"
fi

# Guard against deleting the currently active kernel
if [ "$TARGET_RELEASE" = "$(uname -r)" ]; then
    echo ""
    echo "🚨 ERROR: You are currently booted into this kernel (${TARGET_RELEASE})!"
    echo "Reboot into a different kernel from your GRUB menu before uninstalling this one."
    exit 1
fi

# Confirm target files exist
FILES_TO_REMOVE=(
    "/boot/vmlinuz-${TARGET_RELEASE}"
    "/boot/initrd.img-${TARGET_RELEASE}"
    "/boot/System.map-${TARGET_RELEASE}"
    "/boot/config-${TARGET_RELEASE}"
)

MODULE_DIR="/lib/modules/${TARGET_RELEASE}"

echo ""
echo "Targets identified for removal:"
for file in "${FILES_TO_REMOVE[@]}"; do
    if [ -f "$file" ]; then
        echo "  [FILE]   $file"
    fi
done

if [ -d "$MODULE_DIR" ]; then
    echo "  [DIR]    $MODULE_DIR"
fi

# Check build/source directories in script folder
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
BASE_VERSION="${TARGET_RELEASE%${OS_SUFFIX}}"
SRC_DIR="${SCRIPT_DIR}/linux-${BASE_VERSION}"

REMOVE_SRC=false
if [ -d "$SRC_DIR" ]; then
    echo "  [BUILD]  $SRC_DIR"
fi

echo ""
read -p "Are you sure you want to remove kernel '${TARGET_RELEASE}'? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

if [ -d "$SRC_DIR" ]; then
    read -p "Also delete the build/source folder '${SRC_DIR}'? (y/N): " CONFIRM_SRC
    if [[ "$CONFIRM_SRC" =~ ^[Yy]$ ]]; then
        REMOVE_SRC=true
    fi
fi

# Request sudo and keep alive
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_PID=$!
trap "kill $SUDO_PID 2>/dev/null" EXIT

echo ""
echo "=== Removing /boot artifacts ==="
for file in "${FILES_TO_REMOVE[@]}"; do
    if [ -f "$file" ]; then
        sudo rm -v "$file"
    fi
done

echo "=== Removing kernel modules ==="
if [ -d "$MODULE_DIR" ]; then
    sudo rm -rf "$MODULE_DIR"
    echo "Removed $MODULE_DIR"
fi

if [ "$REMOVE_SRC" = true ] && [ -d "$SRC_DIR" ]; then
    echo "=== Removing build source tree ==="
    rm -rf "$SRC_DIR"
    echo "Removed $SRC_DIR"
fi

echo "=== Updating GRUB configuration ==="
if command -v update-grub &>/dev/null; then
    sudo update-grub
elif command -v grub-mkconfig &>/dev/null; then
    sudo grub-mkconfig -o /boot/grub/grub.cfg
else
    echo "Warning: Could not locate update-grub or grub-mkconfig. Update your bootloader manually."
fi

echo ""
echo "================================================================================"
echo "✔ Kernel ${TARGET_RELEASE} successfully removed."
echo "================================================================================"
