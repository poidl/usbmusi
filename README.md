# usbmusi

A simple, display-free jukebox  for Raspberry Pi. Controllable with a numeric keypad (numpad).

### Motivation

You may like this if you:

* want to listen to music without having to use your phone, tablet or PC. I spend all day at the computer and *don't* want to look at a display when I listen to music at night.

* like listening to albums from start to finish, like they did when only records, tapes and CDs existed.

* own a USB DAC you can attach to the Raspberry.

* have an external USB hard drive to store the music.

* have a spare numeric keypad (or normal keyboard) to control the jukebox

* have a pen and paper where you write up the list of albums ("display") stored on the USB drive, for example
  * 001: Michael Jackson - Thriller
  * 002: Nicki Minaj - The Pinkprint

  which corresponds to the folder structure
  ```
  /mnt/
   |--001/
   |  |--Michael Jackson - Thriller/
   |     |--track1.wav
   |     |--track2.wav
   |     |--...
   |--002/
   |  |--Nicki Minaj - The Pinkprint/
   |     |--track1.wav
   |     |--track2.wav
   |     |--...
   
  ```

  where `/mnt` is the mount point of the USB drive. The important part here are the upper-level directory names (`001`, `002`). The directory structure below doesn't matter, the folders `Micheal Jackson...`, and `Nicki Minaj...` are optional. The program finds `.wav`, `.mp3` and `.flac` files with the `find` command.

### Installation

This assumes you run a system with *systemd*, *pulseaudio* and *mplayer* installed, and have a user named `alarm`. The `install.sh` script activates autologin for user `alarm` and appends a line to `alarm`'s `.bashrc`, starting the program `usbmusi.sh` after automatic login. Commands are read from a numeric keypad.

##### Auto-mounting the USB drive

I use an fstab entry to automount `/dev/sda1` on `/mnt`. Obviously this will only work reliably if `/dev/sda1` is always assigned to the USB drive. For me it does the job, since I only ever have one USB drive on the Raspberry. See e.g. [this Arch wiki article](https://wiki.archlinux.org/index.php/Fstab#Automount_with_systemd) and [user `infinite-etcetera`'s post on serverfault.com](https://serverfault.com/questions/766506/automount-usb-drives-with-systemd). 

##### Auto login and automatic start of the application

Take a look at the `install.sh` script.

### Usage

Choose an album from the paper list and read off the number. To start playback, type the number into the keypad and press enter. 

* `*` skips forward one track
* `\` skips backward one track
* `+` increases volume
* `-` decreases volume
* `999[Enter]` exits the program

### Helpful links

* [Arch's PulsAudio/Troubleshooting](https://wiki.archlinux.org/index.php/PulseAudio/Troubleshooting)
* [Ronald van Engelen's alsa_capabilities.sh](https://lacocina.nl/detect-alsa-output-capabilities)

