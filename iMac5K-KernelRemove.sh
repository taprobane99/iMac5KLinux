#!/bin/bash
set -eEuo pipefail

# ==============================================================================
# Visual & Terminal Output Helpers
# ==============================================================================
if [ -t 1 ]; then
    BOLD="\033[1m"
    DIM="\033[2m"
    BLUE="\033[1;34m"
    GREEN="\033[1;32m"
    YELLOW="\033[1;33m"
    RED="\033[1;31m"
    CYAN="\033[1;36m"
    RESET="\033[0m"
else
    BOLD="" DIM="" BLUE="" GREEN="" YELLOW="" RED="" CYAN="" RESET=""
fi

print_banner() {
    echo -e "${BLUE}================================================================================${RESET}"
    echo -e "${BOLD}                 🖥️  5K iMac Linux Kernel Uninstaller                           ${RESET}"
    echo -e "${BLUE}================================================================================${RESET}"
}

info()    { echo -e "  ${BLUE}ℹ${RESET}  $1"; }
success() { echo -e "  ${GREEN}✔${RESET}  $1"; }
warn()    { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
error()   { echo -e "  ${RED}✖${RESET}  $1"; }

# Cleanup & Error Trap
SUDO_PID=""
cleanup() {
    if [ -n "${SUDO_PID}" ]; then
        kill "${SUDO_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Prevent running the script directly as root
if [ "${EUID}" -eq 0 ]; then
    error "Please do not run this script with 'sudo' or as the root user."
    info "Run it normally as your regular user:  ${BOLD}./$(basename "$0")${RESET}"
    info "The script will prompt for your password when removing files."
    exit 1
fi

clear 2>/dev/null || true
print_banner

CURRENT_KERNEL="$(uname -r)"
echo -e "  ${BOLD}Currently Running Kernel:${RESET} ${GREEN}${BOLD}${CURRENT_KERNEL}${RESET} ${DIM}(Protected from removal)${RESET}"
echo ""

# Scan for all kernels in /boot (stripping .old extensions so duplicates are unified)
mapfile -t ALL_KERNELS < <(find /boot -maxdepth 1 -name "vmlinuz-*" 2>/dev/null \
    | sed 's|^/boot/vmlinuz-||' \
    | sed 's|\.old$||' \
    | sort -V -u)

if [ ${#ALL_KERNELS[@]} -eq 0 ]; then
    warn "No kernels found in /boot."
    exit 0
fi

echo -e "${BLUE}--------------------------------------------------------------------------------${RESET}"
echo -e "${BOLD}  Installed Kernels Detected in /boot:${RESET}"
echo -e "${BLUE}--------------------------------------------------------------------------------${RESET}"

REMOVABLE_KERNELS=()
MENU_INDEX=1

for k in "${ALL_KERNELS[@]}"; do
    if [ "$k" = "$CURRENT_KERNEL" ]; then
        echo -e "  ${DIM}[ - ] $k  ${YELLOW}(RUNNING - PROTECTED)${RESET}"
    else
        printf "  ${BOLD}%2d)${RESET}  %s\n" "$MENU_INDEX" "$k"
        REMOVABLE_KERNELS+=("$k")
        MENU_INDEX=$(( MENU_INDEX + 1 ))
    fi
done

echo -e "  ${BOLD} q)${RESET}  Quit"
echo -e "${BLUE}--------------------------------------------------------------------------------${RESET}"

if [ ${#REMOVABLE_KERNELS[@]} -eq 0 ]; then
    warn "Only the currently running kernel is installed. Nothing to remove."
    exit 0
fi

read -r -p "Select a kernel to uninstall [1-${#REMOVABLE_KERNELS[@]}, or 'q']: " SELECTION

if [[ "$SELECTION" =~ ^[Qq]$ ]] || [ -z "$SELECTION" ]; then
    info "Uninstallation cancelled. No changes were made."
    exit 0
fi

if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt ${#REMOVABLE_KERNELS[@]} ]; then
    error "Invalid choice '${SELECTION}'. Aborting."
    exit 1
fi

TARGET_RELEASE="${REMOVABLE_KERNELS[$(( SELECTION - 1 ))]}"

# Double-check guard against deleting the currently active kernel
if [ "$TARGET_RELEASE" = "$CURRENT_KERNEL" ]; then
    echo ""
    error "CRITICAL: You cannot remove the active running kernel (${TARGET_RELEASE})!"
    info "Reboot into another kernel from GRUB first, then run this uninstaller."
    exit 1
fi

# ==============================================================================
# Identify Artifacts & Packages to Remove
# ==============================================================================
echo ""
info "Inspecting files and packages for kernel: ${BOLD}${TARGET_RELEASE}${RESET}"

# Check if this kernel was installed as a Debian package (.deb / dpkg)
INSTALLED_PKGS=()
for pkg in "linux-image-${TARGET_RELEASE}" "linux-headers-${TARGET_RELEASE}" "linux-modules-${TARGET_RELEASE}" "linux-modules-extra-${TARGET_RELEASE}"; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
        INSTALLED_PKGS+=("$pkg")
    fi
done

# Identify /boot files (including .old backup copies created by 'make install')
BOOT_FILES=()
for pattern in \
    "/boot/vmlinuz-${TARGET_RELEASE}"* \
    "/boot/initrd.img-${TARGET_RELEASE}"* \
    "/boot/System.map-${TARGET_RELEASE}"* \
    "/boot/config-${TARGET_RELEASE}"*; do
    for f in $pattern; do
        if [ -e "$f" ]; then
            BOOT_FILES+=("$f")
        fi
    done
done

MODULE_DIR="/lib/modules/${TARGET_RELEASE}"
HEADER_DIR="/usr/src/linux-headers-${TARGET_RELEASE}"

# Detect potential build directories in script folder (e.g. linux-7.3.0, linux-ubuntu-26.10-*)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
MATCHING_SRC_DIRS=()
# Extract base version (e.g., 7.3.0 or 7.0.1)
BASE_VER=$(echo "${TARGET_RELEASE}" | grep -o '^[0-9]\+\.[0-9]\+\.[0-9]\+' || true)

for dir in \
    "${SCRIPT_DIR}/linux-${TARGET_RELEASE}" \
    "${SCRIPT_DIR}/linux-ubuntu-26.10-${BASE_VER}"* \
    "${SCRIPT_DIR}/linux-${BASE_VER}"; do
    for d in $dir; do
        if [ -d "$d" ]; then
            MATCHING_SRC_DIRS+=("$d")
        fi
    done
done

# De-duplicate matching source folders
if [ ${#MATCHING_SRC_DIRS[@]} -gt 0 ]; then
    mapfile -t MATCHING_SRC_DIRS < <(printf "%s\n" "${MATCHING_SRC_DIRS[@]}" | sort -u)
fi

echo ""
echo -e "${YELLOW}--------------------------------------------------------------------------------${RESET}"
echo -e "${BOLD}Targets identified for removal:${RESET}"
echo -e "${YELLOW}--------------------------------------------------------------------------------${RESET}"

if [ ${#INSTALLED_PKGS[@]} -gt 0 ]; then
    echo -e "  ${BOLD}Debian Packages (APT/dpkg):${RESET}"
    for pkg in "${INSTALLED_PKGS[@]}"; do
        echo -e "    ${CYAN}• $pkg${RESET}"
    done
fi

if [ ${#BOOT_FILES[@]} -gt 0 ]; then
    echo -e "  ${BOLD}/boot Artifacts (including .old files):${RESET}"
    for f in "${BOOT_FILES[@]}"; do
        echo -e "    • $f"
    done
fi

if [ -d "$MODULE_DIR" ]; then
    echo -e "  ${BOLD}Kernel Modules:${RESET}"
    echo -e "    • $MODULE_DIR"
fi

if [ -d "$HEADER_DIR" ]; then
    echo -e "  ${BOLD}Kernel Headers:${RESET}"
    echo -e "    • $HEADER_DIR"
fi

if [ ${#MATCHING_SRC_DIRS[@]} -gt 0 ]; then
    echo -e "  ${BOLD}Matching Build/Source Directories Found:${RESET}"
    for d in "${MATCHING_SRC_DIRS[@]}"; do
        echo -e "    ${DIM}• $d${RESET}"
    done
fi
echo -e "${YELLOW}--------------------------------------------------------------------------------${RESET}"
echo ""

read -r -p "Are you sure you want to completely remove '${TARGET_RELEASE}'? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    info "Aborted. No changes were made."
    exit 0
fi

REMOVE_SRC_DIRS=()
if [ ${#MATCHING_SRC_DIRS[@]} -gt 0 ]; then
    echo ""
    for d in "${MATCHING_SRC_DIRS[@]}"; do
        read -r -p "Also delete build folder '$(basename "$d")' to free up disk space? [y/N]: " CONFIRM_SRC
        if [[ "$CONFIRM_SRC" =~ ^[Yy]$ ]]; then
            REMOVE_SRC_DIRS+=("$d")
        fi
    done
fi

# Request sudo and keep alive
echo ""
info "Requesting administrative privileges..."
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_PID=$!

# ==============================================================================
# Removal Process
# ==============================================================================
# 1. If managed by dpkg/apt, purge via APT first
if [ ${#INSTALLED_PKGS[@]} -gt 0 ]; then
    info "Purging Debian package(s) via apt-get: ${INSTALLED_PKGS[*]}..."
    sudo apt-get purge -y "${INSTALLED_PKGS[@]}"
    success "Debian packages purged."
fi

# 2. Clean up any remaining /boot artifacts (vmlinuz, initrd, System.map, config, .old files)
echo ""
info "Cleaning /boot files for ${TARGET_RELEASE}..."
for f in "${BOOT_FILES[@]}"; do
    if [ -e "$f" ]; then
        sudo rm -f "$f"
        echo -e "  ${DIM}Removed: $f${RESET}"
    fi
done
success "/boot cleaned."

# 3. Clean up /lib/modules directory
if [ -d "$MODULE_DIR" ]; then
    info "Removing module directory: ${MODULE_DIR}..."
    sudo rm -rf "$MODULE_DIR"
    success "Modules removed."
fi

# 4. Clean up /usr/src/linux-headers if leftover
if [ -d "$HEADER_DIR" ]; then
    info "Removing header directory: ${HEADER_DIR}..."
    sudo rm -rf "$HEADER_DIR"
    success "Headers removed."
fi

# 5. Clean up requested source build trees
if [ ${#REMOVE_SRC_DIRS[@]} -gt 0 ]; then
    echo ""
    for d in "${REMOVE_SRC_DIRS[@]}"; do
        info "Removing build folder: $d..."
        rm -rf "$d"
        success "Removed $(basename "$d")"
    done
fi

# 6. Update GRUB
echo ""
info "Updating GRUB bootloader..."
if command -v update-grub &>/dev/null; then
    sudo update-grub
elif command -v grub-mkconfig &>/dev/null; then
    sudo grub-mkconfig -o /boot/grub/grub.cfg
else
    warn "Could not locate update-grub or grub-mkconfig. Please update your bootloader manually."
fi

echo ""
echo -e "${GREEN}================================================================================${RESET}"
echo -e "${GREEN}${BOLD}  ✔ Kernel '${TARGET_RELEASE}' and its GRUB entries successfully removed!${RESET}"
echo -e "${GREEN}================================================================================${RESET}"
