#!/usr/bin/env bash
set -euo pipefail

PACKAGES=(
    "plymouth"
    "libplymouth5"
    "plymouth-label"
    "plymouth-theme-spinner"
    "plymouth-theme-ubuntu-text"
)

BASE_URL="https://launchpad.net/~kchsieh/+archive/ubuntu/verification/+files"
VER="24.004.60+git20250831.4a3c171d-0ubuntu9~oem1_amd64.deb"
WORK_DIR="${HOME}/plymouth-kchsieh"

check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        echo "[*] Elevating privileges..."
        exec sudo bash "$0" "$@"
    fi
}

install_5k_plymouth() {
    check_sudo
    echo "[+] Preparing download directory: ${WORK_DIR}"
    mkdir -p "${WORK_DIR}"
    cd "${WORK_DIR}"
    rm -f ./*.deb

    echo "[+] Downloading matching deb packages..."
    for pkg in "${PACKAGES[@]}"; do
        wget -q --show-progress "${BASE_URL}/${pkg}_${VER}"
    done

    echo "[+] Installing packages and allowing downgrade..."
    apt-get --allow-downgrades install -y ./*.deb

    echo "[+] Putting packages on hold to prevent upstream overwrites..."
    apt-mark hold "${PACKAGES[@]}"

    echo "[✓] 5K Plymouth packages successfully installed and locked on hold."
}

uninstall_5k_plymouth() {
    check_sudo
    echo "[+] Unholding packages..."
    apt-mark unhold "${PACKAGES[@]}" || true

    echo "[+] Updating apt repositories..."
    apt-get update

    echo "[+] Reverting to upstream Ubuntu repository packages..."
    apt-get --reinstall install -y "${PACKAGES[@]}"

    echo "[+] Cleaning up downloaded files..."
    rm -rf "${WORK_DIR}"

    echo "[✓] Reverted cleanly to stock distribution Plymouth packages."
}

show_menu() {
    clear
    echo "========================================"
    echo "       5K Plymouth Manager Menu         "
    echo "========================================"
    echo "1) Install 5K Plymouth (OEM build + hold)"
    echo "2) Uninstall 5K Plymouth (Unhold + revert to stock)"
    echo "3) Exit"
    echo "========================================"
    read -rp "Select an option [1-3]: " choice

    case "$choice" in
        1)
            install_5k_plymouth
            ;;
        2)
            uninstall_5k_plymouth
            ;;
        3)
            echo "Exiting."
            exit 0
            ;;
        *)
            echo "Invalid selection."
            exit 1
            ;;
    esac
}

show_menu
