#!/bin/bash
set -e

echo "================================================================================"
echo "⚠️  Make sure you can access your GRUB menu at boot so you can switch"
echo "    back to your original kernel if this one doesn't work."
echo "================================================================================"
echo ""

echo "==========================================="
echo "=== Select Kernel Version to Build ======"
echo "==========================================="
echo "1) Kernel 7.2.3 (Stable)"
echo "2) Kernel 7.3-rc1 (Mainline)"
echo "3) Quit"
echo "==========================================="
read -p "Enter choice [1-3]: " choice

case $choice in
    1)
        KERNEL_VERSION="7.2.3"
        KERNEL_TARBALL="linux-${KERNEL_VERSION}.tar.xz"
        KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v7.x/${KERNEL_TARBALL}"
        ;;
    2)
        KERNEL_VERSION="7.3-rc1"
        KERNEL_TARBALL="linux-${KERNEL_VERSION}.tar.gz"
        KERNEL_URL="https://git.kernel.org/torvalds/t/${KERNEL_TARBALL}"
        ;;
    3)
        echo "Exiting script."
        exit 0
        ;;
    *)
        echo "Error: Invalid choice. Exiting."
        exit 1
        ;;
esac

echo "==========================================="
echo "=== Requesting Administrative Privileges =="
echo "==========================================="
sudo -v

# Keep sudo session alive
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap "kill $SUDO_KEEPALIVE_PID 2>/dev/null" EXIT

# 1. Start tracking time and disk space
START_TIME=$SECONDS
START_USED_MB=$(df -m / | awk 'NR==2 {print $3}')

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PATCH_FILE="${SCRIPT_DIR}/iMac5K-${KERNEL_VERSION}.patch"
SOURCE_DIR="${SCRIPT_DIR}/linux-${KERNEL_VERSION}"

# Verify Debian-based OS and set kernel localversion suffix
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
                echo ""
                echo "=========================================================="
                echo "🚨 UNSUPPORTED DISTRIBUTION 🚨"
                echo "=========================================================="
                echo "This script is only compatible with Debian-based"
                echo "distributions (e.g. Ubuntu, Linux Mint, Debian)."
                echo ""
                echo "Detected: ID='${ID}', ID_LIKE='${ID_LIKE}'"
                echo "Installation cannot proceed."
                echo "=========================================================="
                exit 1
            fi
            ;;
    esac
else
    echo ""
    echo "=========================================================="
    echo "🚨 CANNOT IDENTIFY OPERATING SYSTEM 🚨"
    echo "=========================================================="
    echo "Unable to locate '/etc/os-release'."
    echo "This script is only compatible with Debian-based distributions."
    echo "=========================================================="
    exit 1
fi

echo "=== Detected Suffix: ${OS_SUFFIX} ==="

echo "=== Installing dependencies ==="
sudo apt-get update
sudo apt-get install -y build-essential bison flex libssl-dev libelf-dev libdw-dev bc zstd rsync wget patch gawk

echo "=== Fetching Kernel ${KERNEL_VERSION} ==="
if [ -f "${SCRIPT_DIR}/${KERNEL_TARBALL}" ]; then
    echo "Found existing tarball at ${KERNEL_TARBALL}. Skipping download."
else
    echo "Downloading ${KERNEL_TARBALL}..."
    wget -O "${SCRIPT_DIR}/${KERNEL_TARBALL}" "${KERNEL_URL}"
fi

echo "=== Extracting Kernel ==="
if [ -d "${SOURCE_DIR}" ]; then
    echo ""
    echo "=========================================================="
    echo "🚨 DIRECTORY ALREADY EXISTS 🚨"
    echo "=========================================================="
    echo "The directory 'linux-${KERNEL_VERSION}' already exists in:"
    echo "${SCRIPT_DIR}"
    echo ""
    echo "Extraction aborted to avoid overwriting an existing directory."
    echo "=========================================================="
    exit 1
else
    tar -xf "${SCRIPT_DIR}/${KERNEL_TARBALL}" -C "${SCRIPT_DIR}"
fi

cd "${SOURCE_DIR}"

echo "=== Applying 5K iMac Patch ==="
if [ -f "${PATCH_FILE}" ]; then
    if ! patch -p1 < "${PATCH_FILE}"; then
        echo ""
        echo "=========================================================="
        echo "🚨 PATCH FAILED: Some parts of the patch were rejected. 🚨"
        echo "=========================================================="
        echo "The kernel source code has likely changed in a way that"
        echo "conflicts with your 'iMac5K-${KERNEL_VERSION}.patch' file."
        echo ""
        echo "Don't worry—your system is fine. To fix this:"
        echo "1. Look for '*.rej' files in the 'linux-${KERNEL_VERSION}' folder."
        echo "2. These files show exactly which code blocks (hunks) failed."
        echo "3. Manually insert the rejected hunks into the new kernel code."
        echo "=========================================================="
        exit 1
    fi
else
    echo "Error: Patch file not found at ${PATCH_FILE}"
    exit 1
fi

echo "=== Configuring Kernel ==="
CURRENT_CONFIG="/boot/config-$(uname -r)"

if [ -f "${CURRENT_CONFIG}" ]; then
    echo "Using current kernel configuration: ${CURRENT_CONFIG}"
    cp "${CURRENT_CONFIG}" .config
else
    echo "Current kernel configuration not found. Searching for the most recent config..."
    FALLBACK_CONFIG=$(ls -t /boot/config-* 2>/dev/null | head -n 1)
    
    if [ -n "${FALLBACK_CONFIG}" ] && [ -f "${FALLBACK_CONFIG}" ]; then
        echo "Using most recent configuration found: ${FALLBACK_CONFIG}"
        cp "${FALLBACK_CONFIG}" .config
    else
        echo "Error: No kernel configuration files found in /boot."
        exit 1
    fi
fi

# Label kernel
scripts/config --set-str CONFIG_LOCALVERSION "${OS_SUFFIX}"
# Fix missing system certs error
scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS ""
scripts/config --set-str CONFIG_SYSTEM_REVOCATION_KEYS ""
# Turn off Debug symbols to save build space
scripts/config --enable CONFIG_DEBUG_INFO_NONE
scripts/config --disable CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
scripts/config --disable CONFIG_DEBUG_INFO_DWARF4
scripts/config --disable CONFIG_DEBUG_INFO_DWARF5
scripts/config --disable CONFIG_DEBUG_INFO_BTF
scripts/config --disable CONFIG_DEBUG_INFO_REDUCED
scripts/config --disable CONFIG_DEBUG_INFO_COMPRESSED_NONE
scripts/config --disable CONFIG_DEBUG_INFO_COMPRESSED_ZLIB
scripts/config --disable CONFIG_DEBUG_INFO_COMPRESSED_ZSTD
scripts/config --disable CONFIG_DEBUG_INFO_SPLIT
scripts/config --disable CONFIG_GDB_SCRIPTS
# Compress kernel modules
scripts/config --disable CONFIG_MODULE_COMPRESS_NONE
scripts/config --enable CONFIG_MODULE_COMPRESS_ZSTD

make olddefconfig

echo "=== Building Kernel ==="
make -j$(nproc)

echo "=== Installing Kernel ==="
sudo make INSTALL_MOD_STRIP=1 modules_install
sudo make install

# 2. Stop tracking time and disk space
END_TIME=$SECONDS
END_USED_MB=$(df -m / | awk 'NR==2 {print $3}')

# 3. Calculate totals
ELAPSED=$(( END_TIME - START_TIME ))
HOURS=$(( ELAPSED / 3600 ))
MINUTES=$(( (ELAPSED % 3600) / 60 ))
SECONDS_LEFT=$(( ELAPSED % 60 ))
SPACE_USED_MB=$(( END_USED_MB - START_USED_MB ))

echo "==========================================="
echo "=== Build and Installation Complete ==="
echo "==========================================="
printf "Total Time Taken:      %02d:%02d:%02d\n" $HOURS $MINUTES $SECONDS_LEFT
echo "Total Disk Space Used for Build: ${SPACE_USED_MB} MB"
echo "==========================================="
echo "Reboot to boot into linux-${KERNEL_VERSION}${OS_SUFFIX}."
