#!/usr/bin/env python3
import os
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

CONFIG_DIR = Path.home() / ".config"
MONITORS_XML = CONFIG_DIR / "monitors.xml"

def ensure_monitors_xml():
    """Ensure ~/.config/monitors.xml exists by triggering Mutter's D-Bus interface if missing."""
    if MONITORS_XML.exists():
        return True

    print("monitors.xml not found. Querying Mutter over D-Bus to generate it...")
    # Calls Mutter's ApplyMonitorsConfig with current state to force writing the file
    # If using standard GNOME Wayland, querying via gdbus creates the state
    dbus_cmd = [
        "gdbus", "call", "--session",
        "--dest", "org.gnome.Mutter.DisplayConfig",
        "--object-path", "/org/gnome/Mutter/DisplayConfig",
        "--method", "org.gnome.Mutter.DisplayConfig.GetCurrentState"
    ]
    try:
        res = subprocess.run(dbus_cmd, capture_output=True, text=True, check=True)
        if not MONITORS_XML.exists():
            print("Note: If the file was not written automatically, toggle any display setting once in GNOME Settings.")
    except Exception as e:
        print(f"D-Bus call failed: {e}")

def patch_monitors_xml():
    if not MONITORS_XML.exists():
        print(f"Error: {MONITORS_XML} does not exist. Please toggle scaling once in GNOME Settings and run again.")
        sys.exit(1)

    tree = ET.parse(MONITORS_XML)
    root = tree.getroot()

    modified = False

    # Traverse all configuration blocks (both current and persistent configurations)
    for config in root.findall(".//configuration"):
        for logical_monitor in config.findall("logicalmonitor"):
            for monitor in logical_monitor.findall("monitor"):
                # Inside <monitor>, find the <mode> tag
                mode_elem = monitor.find("mode")
                if mode_elem is not None:
                    # Check if colormode already exists inside <monitor> or next to <mode>
                    colormode_elem = monitor.find("colormode")
                    if colormode_elem is None:
                        colormode_elem = ET.SubElement(monitor, "colormode")
                        colormode_elem.text = "sdr-native"
                        colormode_elem.tail = "\n        "
                        modified = True
                        print(f"Added <colormode>sdr-native</colormode> to monitor.")
                    elif colormode_elem.text != "sdr-native":
                        colormode_elem.text = "sdr-native"
                        modified = True
                        print(f"Updated <colormode> to sdr-native.")
                    else:
                        print("Monitor already set to sdr-native.")

    if modified:
        # Create a backup
        backup_path = MONITORS_XML.with_suffix(".xml.bak")
        MONITORS_XML.rename(backup_path)
        print(f"Backup created at: {backup_path}")

        # Format and save
        tree.write(MONITORS_XML, encoding="utf-8", xml_declaration=False)
        print(f"Successfully updated {MONITORS_XML}.")
        print("Please log out and log back in for changes to take effect.")
    else:
        print("No changes required.")

if __name__ == "__main__":
    ensure_monitors_xml()
    patch_monitors_xml()
