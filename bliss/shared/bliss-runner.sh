#!/bin/sh
CONF=/etc/config/qpkg.conf
QPKG_NAME="bliss"
INSTALL_PATH=`/sbin/getcfg $QPKG_NAME Install_Path -f ${CONF}`
BLISS_PID=/var/run/bliss.pid
BLISS_PROC=bliss-splash

cd "${INSTALL_PATH}"

if [ -d /usr/local/jre ]; then
    export JAVA_HOME=/usr/local/jre
fi

function get_pid
{
    local name=$1
    ps | grep $name | grep -v grep | awk '{print $1}'
}

function pid_running
{
    local pid=$1
    ps | awk '{print $1}' | grep -q $pid
}


function kill_proc
{
    local pid
    local proc_name="$1"

    # Send the TERM signal
    pid=$(get_pid $proc_name)
    if [ -n "$pid" ]; then
        kill $pid
    else
        return
    fi

    # Wait 8 secs for the process to die
    for i in 1 2 3 4 5 6 7 8; do
        sleep 1
        pid=$(get_pid $proc_name)
        [ -z "$pid" ] && return
    done

    # If it did not die then kill it
    kill -9 $pid
    while true; do
      pid=$(get_pid $proc_name)
      [ -z "$pid" ] && return
    done
}

function kill_pid
{
    local pid=$1

    pid_running $pid || return

    # Send the TERM signal
    kill $pid

    # Wait 8 secs for the process to die
    for i in 1 2 3 4 5 6 7 8; do
        sleep 1
        pid_running $pid || return
    done

    # If it did not die then kill it
    kill -9 $pid
    while true; do
      pid_running $pid || return
    done
}


case "$1" in
  start)
    # Check if the package is enabled
    ENABLED=$(/sbin/getcfg $QPKG_NAME Enable -u -d FALSE -f $CONF)
    if [ "$ENABLED" != "TRUE" ]; then
        echo "$QPKG_NAME is disabled."
        exit 1
    fi

    # Kill any 'zombie' servers
    if [ -e $BLISS_PID ]; then
        kill_pid $(cat $BLISS_PID)
        rm -f $BLISS_PID
    fi
    kill_proc $BLISS_PROC
   
    # Set Bliss Temporary Files dir and launcher (needed for restart after updates)
    export VMARGS=-Djava.io.tmpdir=${INSTALL_PATH}/tmp
    export BLISS_LAUNCHER_PROPERTY="-Dbliss.launcher=${INSTALL_PATH}/bliss-start-after-update.sh"

    # Start the server
    ${INSTALL_PATH}/bin/bliss.sh & 
    
    # Capture the PID
    PID=$!
    echo Process ID $PID
    echo $PID > $BLISS_PID 
    ;;

  stop)
    if [ -e $BLISS_PID ]; then
        kill_pid $(cat $BLISS_PID)
        rm -f $BLISS_PID
    fi
    kill_proc $BLISS_PROC
    ;;

  restart)
    $0 stop
    $0 start
    ;;

  *)
    echo "Usage: $0 {start|stop|restart}"
    exit 1
esac

exit 0

