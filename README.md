# Kernel

Simple script `iMac5K-KernelInstall.sh` to download, build, and install 5K Kernel on iMacs.

Works on Ubuntu, Mint, and other Debian distros.

Only tested on a late 2015 iMac. Backup important files before running.

Needs 7GB Disk Space and 50-70 minutes compile time.

You should be able to easily switch back to your previous kernel from the GRUB menu at boot.

# Fixing screen tearing

Even though 5K works there is a visible tear down the centre of the screen when scrolling fast.
This is fixed on Ubuntu if you run `iMac5K-MutterTearFix-Ubuntu.sh`. For KDE I hear a fix is being made but not yet
finished. Mint - unknown.

# Kernel Parameters (GRUB)

Script `iMac5K-GRUBParams.sh` to fix the following problems (in order) on a 2015 iMac. Unknown if they affect other iMacs.

- R9 M395X GPU power management problem (e.g. Resources app refuses to open)
- Slow booting/shutdown
- Max brightness 400 nits instead of 500 nits

# Audio

Script `iMacAudioInstall.sh` to install Speaker tuning (flat frequency response) I made using a professional microphone. This
should make audio sound much better. Tuned on late 2015 iMac - unknown if will work well on other iMacs.
Currently +/- 7 dB, hoping to retune soon to make it even flatter.

!! Always set the volume very low before playing music/other audio when testing this. There seems
to be a bug that the volume is higher than last set after reboot or logout/login and before adjusting
volume. Do not set the master system volume "Built-in Audio Analogue Surround 4.0" to 100% it's too loud !!

It is essential to install Pavucontrol to set 4 channels as output (Configuration tab), and set volumes to sensible values (Output Devices tab) `sudo apt install pavucontrol`. In the Ubuntu speaker settings you need to choose "iMac Speakers" to use my
tuning.

<img width="600" alt="image" src="https://github.com/user-attachments/assets/9582ea63-e0ce-40f9-a59e-b0b105edfa54" />

# Wide Gamut (P3) Colour Support

You will notice the iMac colours look very saturated. In Ubuntu toggle your display scaling to a different value and back again to generate `~/.config/monitors.xml` (show hidden files in Files to find this from your Home folder).
Then add this line below `<mode>...</mode>` in `monitors.xml` for the screen mode you are using
`<colormode>sdr-native</colormode>`. Log out/in to see changes.

# Font Rendering

Ubuntu/Gnome still uses outline hinting for fonts on HiDPI displays. Some non-GTK apps still apply subpixel-antialiasing, and hinting to fonts on HiDPI displays. This script `iMac5K-FontRenderingFix.` fixes those problems.

# Running .sh scripts

Right-click>Properties>Executable as Program should be ticked, then
drag the .sh file into a terminal window and press enter

<img width="400" alt="image" src="https://github.com/user-attachments/assets/ad442b19-3122-4767-83d9-adaa47f8be8d" />


# Contributions

Please add contributions via opening Issues. There are sure to be quirks for other iMacs that are
different to here. For example, if you have an iMac 2019 and use certain kernel parameters or other
quirks I can add them to my script.
