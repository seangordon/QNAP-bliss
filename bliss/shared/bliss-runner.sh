#!/bin/sh
CONF=/etc/config/qpkg.conf
QPKG_NAME="bliss"
INSTALL_PATH=`/sbin/getcfg $QPKG_NAME Install_Path -f ${CONF}`
BLISS_PID=/var/run/bliss.pid
BLISS_PROC=bliss-splash
CALLED_BY_APP=`cat /proc/$PPID/cmdline | xargs -0 echo | awk '{print $1}'`
WORKING_DIR=$INSTALL_PATH/.bliss
TMP_DIR=$INSTALL_PATH/tmp
STDOUT_LOG=$TMP_DIR/stdout.log

PREFIX=/usr

LN=/bin/ln

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

# Fix for Automatic bliss update: Start bliss if this script is called by java.
if [ $(basename $CALLED_BY_APP) == "java" ]; then
   set start
fi


case "$1" in
  start)
    # Check if the package is enabled
    ENABLED=$(/sbin/getcfg $QPKG_NAME Enable -u -d FALSE -f $CONF)
    CMD_LOG_TOOL="/sbin/log_tool"
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
    
    # Recreate the stdout log so the version checker, later, has something to wait on
    if [ -f $STDOUT_LOG ]; then
        rm $STDOUT_LOG  
        touch $STDOUT_LOG 
    fi

    mkdir -p $TMP_DIR

    # Set Bliss Temporary Files dir and launcher (needed for restart after updates)
    export VMARGS="-Djava.io.tmpdir=${TMP_DIR} -Dbliss_working_directory=${INSTALL_PATH}"
    export BLISS_LAUNCHER_PROPERTY="-Dbliss.launcher=${INSTALL_PATH}/bliss-runner.sh"

    # Start the server
    ${INSTALL_PATH}/bin/bliss.sh > "$STDOUT_LOG" 2>&1 & 
    
    # Capture the PID
    PID=$!
    echo Process ID $PID
    echo $PID > $BLISS_PID 
    
    sleep 5
    if ! kill -0 $PID 2>/dev/null; then
        echo "Didn't start";
        ERROR_LOGS=$(cat $STDOUT_LOG)
        echo $ERROR_LOGS
        $CMD_LOG_TOOL -t2 -uSystem -p127.0.0.1 -mlocalhost -a "$ERROR_LOGS"
        exit 1
    fi

    # Check stdout for the version number. This is a little dodgy! It only quits
    # because there's content after the match. Couldn't find a better way to do it.
    # Prefer this to checking update files, which couples to the update mechanism.
    VERSION=$(tail -f $STDOUT_LOG | grep -m1 -o "[0-9]\{8\}")
    /sbin/setcfg $QPKG_NAME Version $VERSION -f ${CONF}
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

