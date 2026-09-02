# Kernel

Simple script to download, build, and install 5K Kernel on iMacs.

Not tested on all iMacs (I only have a late 2015 iMac). Backup important files before running.

Needs 35GB Disk Space (hopefully less now I disabled debug symbols) and 90 minutes compile time on a 2015 i7 iMac.

You should be able to easily switch back to your previous kernel from the GRUB menu at booth.

# Kernel Parameters

Script to fix the following problems (in order) on a 2015 iMac. Unknown if they affect other iMacs

- R9 M395X GPU power management problem
- Slow booting/shutdown
- Max brightness 400 nits instead of 500 nits

# Audio

Script to install Speaker tuning (flat frequency response) I made using a professional microphone. This
should make audio sound much better. Tuned on late 2015 iMac - unknown if will work well on other iMacs.
Currently +// 7 dB, hoping to retune soon to make it even flatter.

!! Always set the volume very low before playing music/other audio when testing this. There seems
to be a bug that the volume is higher than last set after reboot or logout/login and before adjusting
volume. Do not set the master system volume "Built-in Audio Analogue Surround 4.0" to 100% it's too loud !!

It is essential to install Pavucontrol to set volumes `sudo apt install pavucontrol`

<img width="600" alt="image" src="https://github.com/user-attachments/assets/9582ea63-e0ce-40f9-a59e-b0b105edfa54" />

# Running .sh scripts

Right-click>Properties>Executable as Program should be ticked, then
drag the .sh file into a terminal window and press enter

<img width="400" alt="image" src="https://github.com/user-attachments/assets/ad442b19-3122-4767-83d9-adaa47f8be8d" />


# Contributions

Please add contributions via opening Issues. There are sure to be quirks for other iMacs that are
different to here.
