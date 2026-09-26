## 5K Kernel

Simple one-click script `iMac5K-KernelInstall.sh` to download, build, and install 5K Kernel on iMacs, alongside your existing kernel. You can switch back to your existing kernel from the GRUB menu at boot.

Works on Ubuntu 26.04 LTS. May work on Mint, and other Debian distros.

Works on all pre-2020 5K iMacs except those with Vega GPUs.

Needs 7GB Disk Space and 50-70 minutes compile time.

Credit: thanks to https://github.com/mcirsta/linux-imac-5k/tree/pro1-apple5k-logging which I used to generate my 7.0 patch. My new 7.3 patch is reduced to 190 lines of human-edited code. At some point hopefully this will be mainlined.

Models confirmed working:

| Generation / Release Year | Model Identifier | GPU Option (Family) | 5K Working |
| :--- | :--- | :--- | :--- |
| **Late 2014** | iMac15,1 | R9 M290X (Curacao) | |
| **Late 2014** | iMac15,1 | R9 M295X (Tonga) | |
| **Mid 2015** | iMac15,1 | R9 M290X (Curacao) | |
| **Mid 2015** | iMac15,1 | R9 M295X (Tonga) | |
| **Late 2015** | iMac17,1 | R9 M380 / M390 (Bonaire / Curacao) | ✅ |
| **Late 2015** | iMac17,1 | R9 M395 / M395X (Tonga) | ✅ |
| **Mid 2017** | iMac18,3 | Pro 570 / 575 / 580 (Polaris) | ✅ |
| **2019** | iMac19,1 | Pro 570X / 575X / 580X (Polaris) | |
| **2019** | iMac19,1 | Pro Vega 48 (Vega) | |
| **2020** | iMac20,1 | Pro 5300 / 5500 XT (Navi / RDNA) | |
| **2020** | iMac20,2 | Pro 5700 / 5700 XT (Navi / RDNA) | |
| **2017 (iMac Pro)** | iMacPro1,1 | Pro Vega 56 / 64 / 64X (Vega) | |

## Screen tearing

There may be small tearing artifacts down the centre of the screen.
This is fixed on Ubuntu if you run `iMac5K-MutterTearFix-Ubuntu.sh`.

## Hardware Quirks

Script `iMac5K-GRUBParams.sh` to fix GPU power management problem that causes slow boot/shutdown and some apps not opening.

Script `iMac5K-500nitsfix-alliMacs-untested.sh` to fix max brightness to 500 nits instead of 400 nits using a custom ACPI table

Also, `iMac5K-GRUBFontSize-Ubuntu.sh` fixes tiny text in the GRUB menu.

## Audio

Script `iMacAudioInstall.sh` to install Speaker tuning (flat frequency response +/- 4dB) I made by hand using a UMIK-1 measurement microphone. Tuned on late 2015 iMac

<img width="600" alt="Screenshot From 2026-09-20 14-38-19" src="https://github.com/user-attachments/assets/9d2a066f-663d-4ba8-994f-eb8ec3fba7dd" />

Install Pavucontrol `sudo apt install pavucontrol` to set 4 channels as output (Configuration tab), and set master system volume "Built-in Audio Analogue Surround 4.0" to 80% (Output Devices tab). In audio settings you need to choose "iMac Speakers".

<img width="600" alt="image" src="https://github.com/user-attachments/assets/9582ea63-e0ce-40f9-a59e-b0b105edfa54" />

## Wide Gamut Colour

You will notice the iMac colours look saturated. In display settings toggle scaling to a different value and back again to generate `~/.config/monitors.xml` (show hidden files in Files to find this from your Home folder).
Then add this line below `<mode>...</mode>` in `monitors.xml` for the screen mode you are using
`<colormode>sdr-native</colormode>`. Log out/in to see changes.

<img width="400" alt="Screenshot From 2026-09-06 10-39-45" src="https://github.com/user-attachments/assets/a755507e-ad5b-4fec-bea5-0bb333e2e7f2" />

## Font Rendering

Ubuntu/Gnome still uses outline font hinting on HiDPI displays. Some non-GTK apps still apply subpixel-antialiasing, and font hinting on HiDPI displays. This script `iMac5K-FontRenderingFix.sh` fixes those problems.

## Thunderbolt dock USB ports

These kernel parameters allow access to the USB ports/SD card reader/headphone jack on my Belkin TB3 Dock Pro (might work for other docks)

`usbcore.autosuspend=-1`

## Running .sh scripts

Right-click>Properties>Executable as Program should be ticked, then
drag the .sh file into a terminal window and press enter

<img width="400" alt="image" src="https://github.com/user-attachments/assets/ad442b19-3122-4767-83d9-adaa47f8be8d" />

## Other nice things for your iMac

- https://github.com/taranovegor/mbpfan (generic install) for Fan Control with EMA smoothing
(curve = 45:3,65:7,74:18,82:32,88:50,94:75,100:100 and min_fan1_speed = 850 in etc/mbpfan.conf)
- https://github.com/aunetx/blur-my-shell/tree/refactor/unified-blur-backend (clone this branch) for Liquid Glass
- https://github.com/kem-a/kiwi-kemma for making Ubuntu/Gnome feel at home for Mac users

## Contributions

Please add contributions via opening an Issue. There are sure to be quirks for other iMacs that are
different to here. For example, if you have an iMac 2019 and use certain kernel parameters or other
quirks I can add them to my script.
