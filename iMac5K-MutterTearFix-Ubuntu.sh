#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e 

echo "=== Starting Mutter Tear Fix Installation ==="

echo "-> Enabling source repositories (deb-src) in ubuntu.sources..."
# Safely changes 'Types: deb' to 'Types: deb deb-src' if it hasn't been done already
sudo sed -i 's/^Types: deb$/Types: deb deb-src/g' /etc/apt/sources.list.d/ubuntu.sources

echo "-> Updating package lists..."
sudo apt update

echo "-> Installing all build dependencies..."
sudo apt build-dep -y mutter
# Grabbing the core compiler tools and libxml2-utils for the xmllint warning
sudo apt install -y git meson ninja-build pkg-config libxml2-utils

echo "-> Cloning Mutter repository (tiletear-v2-50.1-rubin)..."
rm -rf mutter-tiletear
git clone -b tiletear-v2-50.1-rubin https://gitlab.gnome.org/adlr/mutter.git mutter-tiletear
cd mutter-tiletear

echo "-> Configuring build environment..."
meson setup build --prefix=/usr --libdir=/usr/lib/x86_64-linux-gnu --buildtype=release

echo "-> Compiling Mutter..."
ninja -C build

echo "-> Installing Mutter system-wide..."
sudo ninja -C build install

echo "-> Enabling TILE_EN=1 in ~/.profile..."
if ! grep -q "TILE_EN=1" ~/.profile; then
    echo 'export TILE_EN=1' >> ~/.profile
fi

echo "=== Installation Complete ==="
echo "Please reboot your system to load the experimental compositor."
