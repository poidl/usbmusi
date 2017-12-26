# https://stackoverflow.com/questions/59895/getting-the-source-directory-of-a-bash-script-from-within
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cp $DIR/usbmusi.sh /home/alarm
chown alarm /home/alarm/usbmusi.sh
chmod 700 /home/alarm/usbmusi.sh
cp $DIR/usbmusi.service /usr/lib/systemd/system
chmod 644 /usr/lib/systemd/system/usbmusi.service
systemctl daemon-reload
systemctl enable sample.service
