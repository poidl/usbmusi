#!/bin/bash

DIR=/mnt
TMP=/tmp/mplayer-control
SEEKLOCK=/tmp/mplayer-control-SEEKLOCK

function errexit() {
    echo "*MYERROR* "$1 1>&2
    exit 1
}

function ctrl_c() {
        # TODO: only kill the ones started in this script
        killall mplayer &> /dev/null
        echo "Cleaning up ..."
        rm $TMP 2>/dev/null
        rm $SEEKLOCK 2>/dev/null
        echo "Exiting ... "
        exit 0
}

function myshutdown() {
        # TODO: only kill the ones started in this script
        killall mplayer &> /dev/null
        echo "Cleaning up ..."
        rm $TMP 2>/dev/null
        echo "Shutting down ... "
        shutdown -h now
}

function process_input() {
    # echo "$1"
    # if [ $1 == '*' ]; then
    #     echo "Skipping forward"
    #     echo "pausing_keep_force pt_step 1" > $TMP
    #     return
    # fi
    if [ "$1" == "999" ]; then
        myshutdown
    fi
    cd $DIR/$1 &> /dev/null
    case $? in
    0)
        killall mplayer &> /dev/null
        play
        ;;
    *)
        echo "ERROR: Directory "$DIR/$1" does not exist"
        ;;
    esac
}

function play() {
    # handle spaces in list https://www.cyberciti.biz/tips/handling-filenames-with-spaces-in-bash.html
    IFS=$'\n'
    LIST=$(find . \( -name '*.flac' -o -name '*.mp3' -o -name '*.wav' \) -print | sort)
    for i in $LIST; do
        echo $i
    done
    rm $TMP 2>/dev/null
    mkfifo $TMP &> /dev/null
    # https://ubuntuforums.org/showthread.php?t=1629000
    # Slave mode commands: http://www.mplayerhq.hu/DOCS/tech/slave.txt
    mplayer -slave -input file=$TMP -novideo -ao pulse $LIST >/dev/null 2>&1 &
    # https://stackoverflow.com/questions/1570262/shell-get-exit-code-of-background-process
    PID=$!
    while   ps | grep "$PID"  | grep -v grep >/dev/null
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
        read -n1 CHARACTER
        # echo $CHARACTER
        if [ -z $CHARACTER ]; then
            echo "Please input directory"
            continue
        elif [ $CHARACTER == "*" ]; then
            echo "skipping forward"
            echo "pausing_keep_force pt_step 1" > $TMP
            continue
        elif [ $CHARACTER == "/" ]; then
            # if seek is locked, skip one track backwards
            if [ -e "$SEEKLOCK" ]; then
                echo "skipping backwards"
                echo "pausing_keep_force pt_step -1" > $TMP
            else 
                echo "seek to start of track"
                echo "seek 0 2" > $TMP
                # apply lock for 2 sec
                (touch $SEEKLOCK; sleep 2; rm $SEEKLOCK) &
            fi
            continue
        elif [ $CHARACTER == "-" ]; then
            echo "decreasing volume"
            echo "volume -1" > $TMP
            continue
        elif [ $CHARACTER == "+" ]; then
            echo "increasing volume"
            echo "volume 1" > $TMP
            continue
        fi 

        # http://www.tldp.org/HOWTO/Bash-Prompt-HOWTO/x405.html
        tput el1
        tput cub1
        # https://stackoverflow.com/questions/12223487/append-to-variable-with-read-command
        read -e -i$CHARACTER NUMBER
        process_input $NUMBER
    done
}

# disable the glob for asterisk '*'
# https://stackoverflow.com/questions/11456403/stop-shell-wildcard-character-expansion
set -f
# trap ctrl-c and call ctrl_c()
# https://rimuhosting.com/knowledgebase/linux/misc/trapping-ctrl-c-in-bash
trap ctrl_c INT
read_input
         