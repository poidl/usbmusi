#!/bin/bash

DIR=/home/stefan/Music
TMP=/tmp/mplayer-control
errexit() {
    echo "*MYERROR* "$1 1>&2
    exit 1
}

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

function ctrl_c() {
        echo "Cleaning up ..."
        rm $TMP 2>/dev/null
        echo "Exiting ... "
        exit 0
}

rm $TMP 2>/dev/null


function process_input() {
    if (( $1==999 )); then
        exit 0
        # shutdown -h now
    fi
    if cd $DIR/$NUMBER; then
        play
        
}

while [ 1 ]; do

    read NUMBER
    until cd $DIR/$NUMBER
    do
        espeak -ven-us+f4 -s170 "Directory does not exist" &> /dev/null
        read NUMBER
    done
    process_input $NUMBER
    # handle spaces in list https://www.cyberciti.biz/tips/handling-filenames-with-spaces-in-bash.html
    IFS=$(echo -en "\n")
    LIST=$(find . \( -name '*.flac' -o -name '*.mp3' -o -name '*.wav' \) -print | sort)
    # echo $LIST
    for i in $LIST; do
        echo $i
    done
    mkfifo $TMP
    # https://ubuntuforums.org/showthread.php?t=1629000
    # Slave mode commands: http://www.mplayerhq.hu/DOCS/tech/slave.txt
    # why xargs? - can't get it to work otherwise if filenames contain spaces
    echo $LIST| xargs -d "\n" mplayer -slave -input file=$TMP -novideo -ao pulse >/dev/null 2>&1 & 

    # https://stackoverflow.com/questions/1570262/shell-get-exit-code-of-background-process
    PID=$!
    # while   ps | grep " $PID "  | grep -v grep > /dev/null
    # do
    #     echo $PID
    #     sleep 3
    # done

    echo "blocking until mplayer exits..."
    wait $PID
    echo "mplayer exited"
    STATUS=$?
    if [ $STATUS==1 ]; then
        errexit "Error mplayer"
    fi;

done
         