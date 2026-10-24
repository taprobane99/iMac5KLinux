## 5K Kernel

<img width="600" alt="Screenshot From 2026-10-21 22-34-27" src="https://github.com/user-attachments/assets/dfa67778-5760-4ba8-979a-ed5703acc53f" />

Intel 5K iMacs can only use 4K resolution with the existing Linux kernel. This 50 line patch properly activates the 5K tiling mode that is used in macOS.

Simple one-click script `iMac5K-KernelInstall.sh` to download, build, and install 5K Kernel on iMacs, alongside your existing kernel.

Works on Ubuntu 26.04 LTS and 26.10. May work on Mint, Zorin, and other Debian distros. Kernel 7.3+ and Mesa 26.3+ recommended.

Works on all 5K iMacs except the 2020 iMac and iMac Pro.

Needs 7GB Disk Space and 50-70 minutes compile time.

Models confirmed working:

| Generation / Release Year | Model Identifier | GPU Option (Family) | 5K Working |
| :--- | :--- | :--- | :---: |
| **Late 2014** | iMac15,1 | R9 M290X (GCN 1) | ❓ |
| **Late 2014** | iMac15,1 | R9 M295X (GCN 3) | ✅ |
| **Mid 2015** | iMac15,1 | R9 M290X (GCN 1) | ❓ |
| **Mid 2015** | iMac15,1 | R9 M295X (GCN 3) | ✅ |
| **Late 2015** | iMac17,1 | R9 M380 / M390 (GCN 2) | ✅ |
| **Late 2015** | iMac17,1 | R9 M395 / M395X (GCN 3) | ✅ |
| **Mid 2017** | iMac18,3 | Pro 570 / 575 / 580 (GCN 4) | ✅ |
| **2019** | iMac19,1 | Pro 570X / 575X / 580X (GCN 4) | ✅ |
| **2019** | iMac19,1 | Pro Vega 48 (GCN 5) | ➖ |
| **2020** | iMac20,1 | Pro 5300 / 5500 XT (RDNA 1) | ➖ |
| **2020** | iMac20,2 | Pro 5700 / 5700 XT (RDNA 1) | ➖ |
| **2017 (iMac Pro)** | iMacPro1,1 | Pro Vega 56 / 64 / 64X (GCN 5) | ➖ |

**Legend:**
* ✅ **Working**: Tiled 5K display working with patch.
* ➖ **Needs Additional Work**: Requires extra methods to activate 5K. You could try using this patch as a base.
* ❓ **Needs Confirmation**: Should work from Kernel 7.3 + Mesa 26.3 onwards thanks to work by Valve.

## Screen tearing

Screen tearing artifacts down the centre of the screen are fixed on Ubuntu if you run `iMac5K-MutterTearFix-Ubuntu.sh`.

## Boot environment

The Plymouth boot splash now supports tiled displays. On Ubuntu this can be tested using `iMac5K-PlymouthTest-Ubuntu.sh`.

To fix tiny text in the GRUB menu and root shell run `iMac5K-GRUBFontSize-Ubuntu.sh`.

## GPU Quirks
To fix GPU power management problem that causes slow boot/shutdown and some apps not opening run `iMac5K-GRUBParams.sh`.

To fix max brightness to 500 nits instead of 400 nits using a custom ACPI table run `iMac5K-500nitsFix.sh`.

To control GPU power mode `GPU-ToggleButton.ini` can be loaded in to the Custom Command Toggle Gnome Extension (https://github.com/StorageB/custom-command-toggle). It appears in Quick Settings. It will default to power saving mode, and switch to a higher performance mode when toggled on.

## Audio

To install Speaker tuning (flat frequency response +/- 4dB) I made by hand using a UMIK-1 measurement microphone run `iMacAudioInstall.sh`. Tuned on late 2015 iMac using the Asahi Audio method. Note: if you have a 2017-2019 iMac you will need to install this first: https://github.com/davidjo/snd_hda_macbookpro

<img width="600" alt="Screenshot From 2026-09-20 14-38-19" src="https://github.com/user-attachments/assets/9d2a066f-663d-4ba8-994f-eb8ec3fba7dd" />

You also need to install Pavucontrol `sudo apt install pavucontrol` to set 4 channels as output (Configuration tab), and set master system volume "Built-in Audio Analogue Surround 4.0" to 79% (Output Devices tab). In Ubuntu audio settings choose "iMac Speakers".

<img width="600" alt="image" src="https://github.com/user-attachments/assets/9582ea63-e0ce-40f9-a59e-b0b105edfa54" />

## Wide Gamut Colour

To set Ubuntu to use the wide gamut colourspace (DCI-P3) available with the iMac display run `iMac5K-WideGamutColour.sh`.

## Font Rendering

Ubuntu/Gnome still uses outline font hinting on HiDPI displays. Some non-GTK apps still apply subpixel-antialiasing, and font hinting on HiDPI displays. To fix these problems run `iMac5K-FontRenderingFix.sh`.

## Belkin Thunderbolt dock USB ports

These kernel parameters allow access to the USB ports/SD card reader/headphone jack on my Belkin TB3 Dock Pro (might work for other docks)

`usbcore.autosuspend=-1`

## Running .sh scripts

Right-click>Properties>Executable as Program should be ticked, then
drag the .sh file into a terminal window and press enter

<img width="400" alt="image" src="https://github.com/user-attachments/assets/ad442b19-3122-4767-83d9-adaa47f8be8d" />

## Other nice things for your iMac

- https://github.com/taranovegor/mbpfan (generic install) for Fan Control with EMA smoothing
(curve = 45:3,65:7,74:18,82:32,88:50,94:75,100:100 and min_fan1_speed = 850 in etc/mbpfan.conf)
- https://github.com/aunetx/blur-my-shell for Liquid Glass
- https://github.com/kem-a/kiwi-kemma for making Ubuntu/Gnome feel at home for Mac users

## Contributions

Please add contributions via opening an Issue. There are sure to be other iMac quirks not listed here.

## Credit

Thanks to the AI-assisted (Claude) discovery at https://github.com/mcirsta/linux-imac-5k/tree/pro1-apple5k-logging which I used to generate my 1,500 line kernel 7.0 patch. My new kernel 7.3 patch is reduced to 50 lines with a combination of human-editing and AI suggestions (Google Gemini). Thanks to Timur Kristóf, https://github.com/MarkPronkin/, and https://github.com/ahmadtv for input, code review, feedback. At some point hopefully this will be mainlined.
