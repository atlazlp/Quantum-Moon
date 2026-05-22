Optional kernel quirk for ALC897 front-panel TRRS headset jacks (mic + headphones on one plug).

If desktop audio still dominates the mic when hardware-muted, install and reboot:

  sudo install -m644 alsa-realtek-alc897-headset.conf /etc/modprobe.d/
  sudo mkinitcpio -P   # only if you use mkinitcpio and the file is in initramfs path
  reboot

Then run: ~/.config/caelestia/scripts/audio-setup-analog-mic.sh

Try other models if headset-mic does not help (edit the file):
  headset-mic, dell-headset-mic, alc897-headset

Revert: sudo rm /etc/modprobe.d/alsa-realtek-alc897-headset.conf && reboot
