#!/bin/bash

DIR=/home/stefan/Music
TMP=/tmp/mplayer-control

function errexit() {
    echo "*MYERROR* "$1 1>&2
    exit 1
}

function ctrl_c() {
        # TODO: only kill the ones started in this script
        killall mplayer &> /dev/null
        echo "Cleaning up ..."
        rm $TMP 2>/dev/null
        echo "Exiting ... "
        exit 0
}

function process_input() {
    if (( $1==999 )); then
        ctrl_c
        # shutdown -h now
    fi
    cd $DIR/$1
    case $? in
    0)
        killall mplayer &> /dev/null
        play
        ;;
    *)
        espeak -ven-us+f4 -s170 "Directory does not exist" &> /dev/null
        ;;
    esac
}

function play() {
    # handle spaces in list https://www.cyberciti.biz/tips/handling-filenames-with-spaces-in-bash.html
    IFS=$(echo -en "\n")
    LIST=$(find . \( -name '*.flac' -o -name '*.mp3' -o -name '*.wav' \) -print | sort)
    # echo $LIST
    for i in $LIST; do
        echo $i
    done
    mkfifo $TMP &> /dev/null
    # https://ubuntuforums.org/showthread.php?t=1629000
    # Slave mode commands: http://www.mplayerhq.hu/DOCS/tech/slave.txt
    # why xargs? - can't get it to work otherwise if filenames contain spaces
    echo $LIST| xargs -d "\n" mplayer -slave -input file=$TMP -novideo -ao pulse >/dev/null 2>&1 & 

    # https://stackoverflow.com/questions/1570262/shell-get-exit-code-of-background-process
    PID=$!
    while   ps | grep " $PID "  | grep -v grep > /dev/null
    do
        read_input
    done

    # echo "blocking until mplayer exits..."
    wait $PID
    echo "mplayer exited"
    STATUS=$?
    if [ $STATUS==1 ]; then
        errexit "Error mplayer"
    fi;
}

function read_input() {
    while [ 1 ]; do
        read NUMBER
        process_input $NUMBER
    done
}

# trap ctrl-c and call ctrl_c()
# https://rimuhosting.com/knowledgebase/linux/misc/trapping-ctrl-c-in-bash
trap ctrl_c INT
rm $TMP 2>/dev/null
read_input
         