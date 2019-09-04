#!/usr/bin/env bash
### BEGIN INIT INFO
# Provides:          pihole-FTL
# Required-Start:    $remote_fs $syslog
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: pihole-FTL daemon
# Description:       Enable service provided by pihole-FTL daemon
### END INIT INFO

FTLUSER=pihole
PIDFILE=/var/run/pihole-FTL.pid

get_pid() {
    # First, try to obtain PID from PIDFILE
    if [ -s "${PIDFILE}" ]; then
        cat "${PIDFILE}"
        return
    fi

    # If the PIDFILE is empty or not available, obtain the PID using pidof
    pidof "pihole-FTL" | awk '{print $(NF)}'
}

is_running() {
    ps "$(get_pid)" > /dev/null 2>&1
}


# Start the service
start() {
  if is_running; then
    echo "pihole-FTL is already running"
  else
    USER=$FTLUSER
    source /opt/pihole/fix_files.sh

    echo "nameserver 127.0.0.1" | /sbin/resolvconf -a lo.piholeFTL
    if setcap CAP_NET_BIND_SERVICE,CAP_NET_RAW,CAP_NET_ADMIN+eip "$(which pihole-FTL)"; then
      su -s /bin/sh -c "/usr/bin/pihole-FTL" "$FTLUSER"
    else
      echo "Warning: Starting pihole-FTL as root because setting capabilities is not supported on this system"
      pihole-FTL
    fi
    echo
  fi
}

# Stop the service
stop() {
  if is_running; then
    /sbin/resolvconf -d lo.piholeFTL
    kill "$(get_pid)"
    for i in {1..5}; do
      if ! is_running; then
        break
      fi

      echo -n "."
      sleep 1
    done
    echo

    if is_running; then
      echo "Not stopped; may still be shutting down or shutdown may have failed, killing now"
      kill -9 "$(get_pid)"
      exit 1
    else
      echo "Stopped"
    fi
  else
    echo "Not running"
  fi
  echo
}

# Indicate the service status
status() {
  if is_running; then
    echo "[ ok ] pihole-FTL is running"
    exit 0
  else
    echo "[    ] pihole-FTL is not running"
    exit 1
  fi
}


### main logic ###
case "$1" in
  stop)
        stop
        ;;
  status)
        status
        ;;
  start|restart|reload|condrestart)
        stop
        start
        ;;
  *)
        echo $"Usage: $0 {start|stop|restart|reload|status}"
        exit 1
esac

exit 0
