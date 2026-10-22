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

TOTAL_STEPS=7
CURRENT_STEP=0

print_banner() {
    echo -e "${BLUE}================================================================================${RESET}"
    echo -e "${BOLD}                 🖥️  5K iMac Custom Linux Kernel Installer                      ${RESET}"
    echo -e "${BLUE}================================================================================${RESET}"
}

print_step() {
    CURRENT_STEP=$(( CURRENT_STEP + 1 ))
    echo ""
    echo -e "${BLUE}--------------------------------------------------------------------------------${RESET}"
    echo -e "${CYAN}${BOLD}[Step ${CURRENT_STEP}/${TOTAL_STEPS}] $1${RESET}"
    echo -e "${BLUE}--------------------------------------------------------------------------------${RESET}"
}

info()    { echo -e "  ${BLUE}ℹ${RESET}  $1"; }
success() { echo -e "  ${GREEN}✔${RESET}  $1"; }
warn()    { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
error()   { echo -e "  ${RED}✖${RESET}  $1"; }

# POSIX-compliant disk space helpers (compatible with both GNU and Rust uutils df)
get_free_mb() {
    df -Pk "$1" | awk 'NR==2 {print int($4 / 1024)}'
}

get_used_mb() {
    df -Pk "$1" | awk 'NR==2 {print int($3 / 1024)}'
}

# HTTP helper that works with either wget or curl before apt runs
fetch_url() {
    local url="$1"
    if command -v wget &> /dev/null; then
        wget -qO- --timeout=10 --tries=2 "$url" 2>/dev/null || true
    elif command -v curl &> /dev/null; then
        curl -fsSL --connect-timeout 10 --max-time 15 "$url" 2>/dev/null || true
    else
        error "Neither 'wget' nor 'curl' is installed to query remote versions."
        info "Please run: sudo apt update && sudo apt install wget"
        exit 1
    fi
}

# Cleanup & Error Trap
SUDO_KEEPALIVE_PID=""
cleanup() {
    if [ -n "${SUDO_KEEPALIVE_PID}" ]; then
        kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

on_error() {
    local exit_code=$?
    local line_no=$1
    echo ""
    echo -e "${RED}================================================================================${RESET}"
    echo -e "${RED}${BOLD}  ✖ INSTALLATION STOPPED UNEXPECTEDLY (Line ${line_no}, Exit Code ${exit_code})${RESET}"
    echo -e "${RED}================================================================================${RESET}"
    echo -e "  Something went wrong during the step above. Don't worry—your currently"
    echo -e "  installed system and kernel have not been harmed."
    echo -e "${RED}================================================================================${RESET}"
}
trap 'on_error $LINENO' ERR

# ==============================================================================
# Pre-Flight Checks (OS, Permissions, Environment)
# ==============================================================================
clear 2>/dev/null || true
print_banner
echo ""
echo -e "  ${YELLOW}${BOLD}⚠️  IMPORTANT BOOT NOTE:${RESET}"
echo -e "  Make sure you can access your ${BOLD}GRUB boot menu${RESET} when turning on your Mac"
echo -e "  so you can easily switch back to your original kernel if needed."
echo ""

# Prevent running the entire script directly as root (avoids root-owned build files)
if [ "${EUID}" -eq 0 ]; then
    error "Please do not run this script with 'sudo' or as the root user."
    info "Run it normally as your regular user:  ${BOLD}./$(basename "$0")${RESET}"
    info "The script will ask for your password when administrative rights are needed."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Verify Debian-based OS and set kernel localversion suffix
if [ -f /etc/os-release ]; then
    . /etc/os-release
    ID="${ID:-unknown}"
    ID_LIKE="${ID_LIKE:-}"
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
                echo -e "${RED}================================================================================${RESET}"
                echo -e "${RED}${BOLD}  ✖ UNSUPPORTED LINUX DISTRIBUTION${RESET}"
                echo -e "${RED}================================================================================${RESET}"
                echo -e "  This installer is designed for Debian-based distributions"
                echo -e "  (such as Ubuntu, Linux Mint, Pop!_OS, and Debian)."
                echo -e ""
                echo -e "  Detected System: ID='${ID}', ID_LIKE='${ID_LIKE}'"
                echo -e "${RED}================================================================================${RESET}"
                exit 1
            fi
            ;;
    esac
else
    error "Cannot identify operating system ('/etc/os-release' is missing)."
    info "This installer only supports Debian-based distributions."
    exit 1
fi

# Check available free disk space (require at least 10 GB / 10240 MB)
FREE_SPACE_MB=$(get_free_mb "${SCRIPT_DIR}")
if [ "${FREE_SPACE_MB}" -lt 10240 ]; then
    warn "Low disk space detected: $(( FREE_SPACE_MB / 1024 )) GB available."
    warn "At least 10 GB of free space is recommended to compile the kernel."
    read -r -p "  Continue anyway? [y/N]: " space_continue
    if [[ ! "${space_continue}" =~ ^[Yy]$ ]]; then
        info "Installation cancelled."
        exit 0
    fi
fi

# ==============================================================================
# Interactive Kernel Version Menu
# ==============================================================================
echo -e "${BLUE}================================================================================${RESET}"
echo -e "${BOLD}  Select Kernel Version to Build & Install${RESET} ${DIM}(Detected suffix: ${OS_SUFFIX})${RESET}"
echo -e "${BLUE}================================================================================${RESET}"
echo -e "  ${BOLD}1)${RESET} Kernel 7.3.0         ${GREEN}(Stable - Oct 2026)${RESET}"
echo -e "  ${BOLD}2)${RESET} Kernel 7.3.x         ${CYAN}(Auto-detect latest 7.3 point release)${RESET}"
echo -e "  ${BOLD}3)${RESET} Kernel 7.4-rc1       ${DIM}(Release Candidate / Testing)${RESET}"
echo -e "  ${BOLD}4)${RESET} Ubuntu 26.10 Kernel  ${GREEN}(Official Ubuntu 26.10 Launchpad release)${RESET}"
echo -e "  ${BOLD}5)${RESET} Quit"
echo -e "${BLUE}--------------------------------------------------------------------------------${RESET}"
read -r -p "  Enter your choice [1-5]: " choice

case $choice in
    1)
        KERNEL_VERSION="7.3"
        PATCH_VERSION="7.3.0"
        KERNEL_TARBALL="linux-${KERNEL_VERSION}.tar.xz"
        KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v7.x/${KERNEL_TARBALL}"
        USE_GIT=false
        ;;
    2)
        info "Checking cdn.kernel.org for the latest 7.3.x release..."
        INDEX_HTML=$(fetch_url "https://cdn.kernel.org/pub/linux/kernel/v7.x/")

        LATEST_TARBALL=$(echo "${INDEX_HTML}" | grep -o 'linux-7\.3\.[0-9]*\.tar\.xz' | sort -V | tail -n 1 || true)
        if [ -z "${LATEST_TARBALL}" ]; then
            error "Could not find any 7.3.x point releases on cdn.kernel.org (or check your internet connection)."
            info "If 7.3.1 has not been released yet, please re-run and choose Option 1 (Kernel 7.3.0)."
            exit 1
        fi

        KERNEL_VERSION="${LATEST_TARBALL#linux-}"
        KERNEL_VERSION="${KERNEL_VERSION%.tar.xz}"
        PATCH_VERSION="7.3.0"
        KERNEL_TARBALL="${LATEST_TARBALL}"
        KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v7.x/${KERNEL_TARBALL}"
        success "Found latest release: ${BOLD}Linux ${KERNEL_VERSION}${RESET}"
        USE_GIT=false
        ;;
    3)
        KERNEL_VERSION="7.4-rc1"
        PATCH_VERSION="7.4-rc1"
        KERNEL_TARBALL="linux-${KERNEL_VERSION}.tar.gz"
        KERNEL_URL="https://git.kernel.org/torvalds/t/${KERNEL_TARBALL}"
        USE_GIT=false
        ;;
    4)
        info "Querying Launchpad for the latest Ubuntu 26.10 kernel version..."
        USE_GIT=true
        # Launchpad repositories use the first word of the Ubuntu codename ('stonking' for 26.10)
        GIT_URL="https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/stonking"
        GIT_BRANCH="master"
        UBUNTU_PKG_VER=""

        # Tier 1: Query Launchpad's official REST API (avoids git.launchpad.net cgit 503 errors)
        LP_API_URL="https://api.launchpad.net/1.0/ubuntu/+archive/primary?ws.op=getPublishedSources&exact_match=true&source_name=linux&distro_series=/1.0/ubuntu/stonking&status=Published"
        LP_JSON=$(fetch_url "${LP_API_URL}")
        if [ -n "${LP_JSON}" ]; then
            UBUNTU_PKG_VER=$(echo "${LP_JSON}" | grep -o '"source_package_version": *"[^"]*"' | head -n 1 | cut -d'"' -f4 || true)
        fi

        # Tier 2: Fallback to 'git ls-remote' against the Turnip Git backend if git is installed
        if [ -z "${UBUNTU_PKG_VER}" ] && command -v git &> /dev/null; then
            UBUNTU_PKG_VER=$(git ls-remote --tags --refs "${GIT_URL}" "refs/tags/Ubuntu-*" 2>/dev/null \
                | awk -F'refs/tags/Ubuntu-' '{print $2}' \
                | sed 's/^[0-9]\+\.[0-9]\+-//' \
                | tr '_' '~' \
                | sort -V | tail -n 1 || true)
        fi

        # Extract upstream kernel version from Ubuntu package version (e.g., 7.3.0-9.9 -> 7.3.0)
        if [ -n "${UBUNTU_PKG_VER}" ]; then
            FULL_KVER="${UBUNTU_PKG_VER%%-*}"
            BASE_KVER=$(echo "${FULL_KVER}" | cut -d. -f1,2)
            PATCH_VERSION="${BASE_KVER}.0"
            KERNEL_VERSION="ubuntu-26.10-${FULL_KVER}"
            success "Detected Ubuntu 26.10 Kernel: ${BOLD}Linux ${FULL_KVER}${RESET} ${DIM}(Package: ${UBUNTU_PKG_VER}, Branch: ${GIT_BRANCH})${RESET}"
        else
            # Tier 3: Safe fallback to 7.3.0; exact version is read from local Makefile after cloning
            FULL_KVER="7.3.0"
            PATCH_VERSION="7.3.0"
            KERNEL_VERSION="ubuntu-26.10-${FULL_KVER}"
            info "Using Ubuntu 26.10 release baseline (${BOLD}Linux ${FULL_KVER}${RESET}); exact revision will be verified after cloning."
        fi
        ;;
    5)
        info "Exiting installer. No changes were made."
        exit 0
        ;;
    *)
        error "Invalid selection '${choice}'. Exiting."
        exit 1
        ;;
esac

PATCH_FILE="${SCRIPT_DIR}/iMac5K-${PATCH_VERSION}.patch"
SOURCE_DIR="${SCRIPT_DIR}/linux-${KERNEL_VERSION}"

# Verify the patch file exists BEFORE doing any heavy lifting
if [ ! -f "${PATCH_FILE}" ]; then
    echo ""
    error "Required patch file was not found:"
    info "Expected location: ${BOLD}${PATCH_FILE}${RESET}"
    info "Make sure 'iMac5K-${PATCH_VERSION}.patch' is in the same folder as this script."
    exit 1
fi
success "Verified patch file: $(basename "${PATCH_FILE}")"

# Check if source directory already exists from a previous run
if [ -d "${SOURCE_DIR}" ]; then
    echo ""
    warn "An existing build folder '${BOLD}linux-${KERNEL_VERSION}${RESET}' was found in:"
    info "${SCRIPT_DIR}"
    read -r -p "  Would you like to delete it and start a clean build? [y/N]: " delete_existing
    if [[ "${delete_existing}" =~ ^[Yy]$ ]]; then
        info "Removing old 'linux-${KERNEL_VERSION}' directory..."
        rm -rf "${SOURCE_DIR}"
        success "Old build directory removed."
    else
        info "Build cancelled to avoid overwriting existing files."
        exit 0
    fi
fi

# ==============================================================================
# Step 1: Request Administrative Privileges
# ==============================================================================
print_step "Requesting Administrative Privileges (sudo)"
info "Your password is required to install build tools and the final kernel."
sudo -v
success "Administrative privileges granted."

# Keep sudo session alive in the background until the script finishes
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!

# Start tracking time and disk space
START_TIME=$SECONDS
START_USED_MB=$(get_used_mb "${SCRIPT_DIR}")

# ==============================================================================
# Step 2: Install Build Dependencies
# ==============================================================================
print_step "Installing Required Build Tools"
info "Updating package lists and installing compiler dependencies via apt..."
sudo apt-get update -qq
sudo apt-get install -y \
    build-essential bison flex libssl-dev libelf-dev libdw-dev \
    bc zstd rsync wget patch gawk git
success "All required build packages are installed."

# ==============================================================================
# Step 3: Download & Extract Kernel Source
# ==============================================================================
print_step "Fetching and Extracting Linux Kernel Source"
if [ "$USE_GIT" = true ]; then
    info "Cloning Ubuntu 26.10 kernel ('${GIT_BRANCH}' branch) from Launchpad..."
    git clone --depth 1 -b "${GIT_BRANCH}" "${GIT_URL}" "${SOURCE_DIR}"

    # Confirm exact kernel & Ubuntu package version from the cloned source files
    if [ -f "${SOURCE_DIR}/Makefile" ]; then
        CLONED_KVER=$(make -s -C "${SOURCE_DIR}" kernelversion 2>/dev/null || true)
        CLONED_PKG_VER=""
        if [ -f "${SOURCE_DIR}/debian.master/changelog" ]; then
            CLONED_PKG_VER=$(head -n 1 "${SOURCE_DIR}/debian.master/changelog" | sed -n 's/^linux (\([^)]*\)).*/\1/p' || true)
        fi
        if [ -n "${CLONED_KVER}" ]; then
            success "Cloned Ubuntu 26.10 source: ${BOLD}Linux ${CLONED_KVER}${RESET} ${DIM}${CLONED_PKG_VER:+(Ubuntu package: ${CLONED_PKG_VER})}${RESET}"
        fi
    else
        success "Ubuntu 26.10 kernel repository cloned to 'linux-${KERNEL_VERSION}'."
    fi
else
    if [ -f "${SCRIPT_DIR}/${KERNEL_TARBALL}" ]; then
        success "Found existing archive '${KERNEL_TARBALL}'. Skipping download."
    else
        info "Downloading ${KERNEL_TARBALL} from kernel.org..."
        wget -c --show-progress -O "${SCRIPT_DIR}/${KERNEL_TARBALL}.part" "${KERNEL_URL}"
        mv "${SCRIPT_DIR}/${KERNEL_TARBALL}.part" "${SCRIPT_DIR}/${KERNEL_TARBALL}"
        success "Download complete."
    fi

    info "Extracting ${KERNEL_TARBALL} (please wait, unpacking thousands of files)..."
    tar -xf "${SCRIPT_DIR}/${KERNEL_TARBALL}" -C "${SCRIPT_DIR}"
    success "Kernel source extracted to 'linux-${KERNEL_VERSION}'."
fi

cd "${SOURCE_DIR}"

# ==============================================================================
# Step 4: Apply 5K iMac Hardware Patch
# ==============================================================================
print_step "Applying 5K iMac Hardware Patch"
info "Testing patch compatibility against ${KERNEL_VERSION}..."

if ! patch -p1 --dry-run -s < "${PATCH_FILE}" 2>/dev/null; then
    echo ""
    echo -e "${RED}================================================================================${RESET}"
    echo -e "${RED}${BOLD}  🚨 PATCH FAILED: Code Conflicts Detected${RESET}"
    echo -e "${RED}================================================================================${RESET}"
    echo -e "  The kernel source code has changed in a way that conflicts with:"
    echo -e "  ${BOLD}$(basename "${PATCH_FILE}")${RESET}"
    echo -e ""
    echo -e "  Running patch output to show conflicting files:"
    echo -e "${DIM}--------------------------------------------------------------------------------${RESET}"
    patch -p1 < "${PATCH_FILE}" || true
    echo -e "${DIM}--------------------------------------------------------------------------------${RESET}"
    echo -e "  ${GREEN}Don't worry—your system has not been modified.${RESET} To inspect the failure:"
    echo -e "  1. Look for '${BOLD}*.rej${RESET}' files inside the 'linux-${KERNEL_VERSION}' folder."
    echo -e "  2. These show which code blocks (hunks) failed to apply."
    echo -e "${RED}================================================================================${RESET}"
    exit 1
fi

patch -p1 < "${PATCH_FILE}"
success "5K iMac patch applied cleanly!"

# ==============================================================================
# Step 5: Configure the Kernel
# ==============================================================================
print_step "Configuring Kernel Build Options"
CURRENT_CONFIG="/boot/config-$(uname -r)"

if [ "$USE_GIT" = true ]; then
    LATEST_GENERIC_CONFIG=$(find /boot -maxdepth 1 -name 'config-*-generic' 2>/dev/null | sort -V | tail -n 1 || true)

    if [ -n "${LATEST_GENERIC_CONFIG}" ] && [ -f "${LATEST_GENERIC_CONFIG}" ]; then
        info "Base configuration: ${BOLD}${LATEST_GENERIC_CONFIG}${RESET}"
        cp "${LATEST_GENERIC_CONFIG}" .config
    else
        error "No kernel configuration files ending in 'generic' were found in /boot."
        exit 1
    fi
else
    if [ -f "${CURRENT_CONFIG}" ]; then
        info "Base configuration (running kernel): ${BOLD}${CURRENT_CONFIG}${RESET}"
        cp "${CURRENT_CONFIG}" .config
    else
        warn "Running kernel configuration not found. Searching /boot for newest config..."
        FALLBACK_CONFIG=$(find /boot -maxdepth 1 -name 'config-*' 2>/dev/null | sort -V | tail -n 1 || true)

        if [ -n "${FALLBACK_CONFIG}" ] && [ -f "${FALLBACK_CONFIG}" ]; then
            info "Base configuration: ${BOLD}${FALLBACK_CONFIG}${RESET}"
            cp "${FALLBACK_CONFIG}" .config
        else
            error "No kernel configuration files found in /boot."
            exit 1
        fi
    fi
fi

info "Applying custom build flags (disabling debug symbols, enabling ZSTD module compression)..."
# Label kernel
scripts/config --set-str CONFIG_LOCALVERSION "${OS_SUFFIX}"
# Fix missing system certs error on Debian/Ubuntu derivatives
scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS ""
scripts/config --set-str CONFIG_SYSTEM_REVOCATION_KEYS ""
# Turn off Debug symbols to save significant disk space and build time
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
# Compress kernel modules with ZSTD
scripts/config --disable CONFIG_MODULE_COMPRESS_NONE
scripts/config --enable CONFIG_MODULE_COMPRESS_ZSTD

make olddefconfig
FINAL_RELEASE=$(make -s kernelrelease)
success "Kernel configured! Target release name: ${BOLD}${FINAL_RELEASE}${RESET}"

# ==============================================================================
# Step 6: Compile the Kernel
# ==============================================================================
CPU_THREADS=$(nproc)
print_step "Compiling Kernel (Using ${CPU_THREADS} CPU Threads)"
echo -e "  ${YELLOW}☕ Grab a coffee!${RESET} Compiling the Linux kernel takes ${BOLD}15 to 45 minutes${RESET}"
echo -e "     depending on your processor. Your iMac's fan will likely spin up—"
echo -e "     this is completely normal."
echo ""

make -j"${CPU_THREADS}"
success "Kernel compilation finished!"

# ==============================================================================
# Step 7: Install Modules & Kernel Image
# ==============================================================================
print_step "Installing Kernel Modules and Boot Image"
info "Installing stripped kernel modules to /lib/modules/${FINAL_RELEASE}..."
sudo make INSTALL_MOD_STRIP=1 modules_install

info "Installing kernel image to /boot and updating GRUB bootloader..."
sudo make install
success "Kernel and boot files installed."

# ==============================================================================
# Summary & Completion
# ==============================================================================
END_TIME=$SECONDS
END_USED_MB=$(get_used_mb "${SCRIPT_DIR}")

ELAPSED=$(( END_TIME - START_TIME ))
HOURS=$(( ELAPSED / 3600 ))
MINUTES=$(( (ELAPSED % 3600) / 60 ))
SECONDS_LEFT=$(( ELAPSED % 60 ))
SPACE_USED_MB=$(( END_USED_MB - START_USED_MB ))
if [ "${SPACE_USED_MB}" -lt 0 ]; then SPACE_USED_MB=0; fi

echo ""
echo -e "${GREEN}================================================================================${RESET}"
echo -e "${GREEN}${BOLD}  🎉 BUILD AND INSTALLATION COMPLETE!${RESET}"
echo -e "${GREEN}================================================================================${RESET}"
printf "  ${BOLD}Total Time Taken:${RESET}        %02dh %02dm %02ds\n" $HOURS $MINUTES $SECONDS_LEFT
echo -e "  ${BOLD}Disk Space Used:${RESET}         ~${SPACE_USED_MB} MB"
echo -e "  ${BOLD}Installed Kernel:${RESET}        ${CYAN}${FINAL_RELEASE}${RESET}"
echo -e "${GREEN}--------------------------------------------------------------------------------${RESET}"
echo -e "  ${BOLD}Next Steps:${RESET}"
echo -e "  1. Restart your iMac to boot into ${BOLD}${FINAL_RELEASE}${RESET}."
echo -e "  2. Once you have restarted and confirmed everything works, you can safely"
echo -e "     delete the '${BOLD}linux-${KERNEL_VERSION}${RESET}' build folder to reclaim disk space."
echo -e "${GREEN}================================================================================${RESET}"
