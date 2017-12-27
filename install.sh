# https://stackoverflow.com/questions/59895/getting-the-source-directory-of-a-bash-script-from-within
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cp $DIR/usbmusi.sh /home/alarm
chown alarm /home/alarm/usbmusi.sh
chmod 700 /home/alarm/usbmusi.sh

# autologin to virtual console
# https://wiki.archlinux.org/index.php/getty#Automatic_login_to_virtual_console
mkdir /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf <<- EOM
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin alarm --noclear %I $TERM
EOM

# append to .bashrc
echo "./usbmusi.sh" >> .bashrc
