#!/bin/ksh
# CarPlay map on the cluster: runs stream-player while CarPlay sends its
# cluster video, and stops it when CarPlay stops.
#
#   carplay_cluster.sh <dio_manager pid>
#
# Started by libcarplay_cluster.so when dio_manager (CarPlay) starts; ends
# when that dio_manager does. harman-f's libaltscreen111.so, in the same
# process, receives CarPlay's cluster stream and serves it as H.264 on
# 127.0.0.1:19820, at the cluster map window's size (set by the installer).
# While it does, it writes "streaming" to its state file.
# The player draws that stream on the cluster exactly as it draws Android
# Auto's, and on SIGTERM gives the cluster back to the stock map.
# expr is in /mnt/app/armle/usr/bin on this unit (Golf R log: "expr: cannot execute").
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/eso/bin:/mnt/app/eso/bin:/mnt/app/navigation:/mnt/app/armle/bin:/mnt/app/armle/usr/bin
export PATH

OWNER=${1:-}
PLAYER=/mnt/app/navigation/stream-player
SOURCE=tcp://127.0.0.1:19820
STATE=/tmp/mibr-carplay111.state
PIDFILE=/tmp/carplay_cluster.pid
PLAYER_LOG=/tmp/stream-player-carplay.log
PLAYER_PID=
PLAYER_START=0

log() { echo "carplay_cluster $*"; }

[ -n "$OWNER" ] || { log "no dio_manager pid given"; exit 2; }
[ -x "$PLAYER" ] || { log "no player at $PLAYER"; exit 3; }

# One supervisor at a time: a dio_manager restart starts a new one.
if [ -r "$PIDFILE" ]; then
    OLD=`cat "$PIDFILE" 2>/dev/null`
    if [ -n "$OLD" ] && [ "$OLD" != $$ ] && kill -0 "$OLD" 2>/dev/null; then
        kill "$OLD" 2>/dev/null
        sleep 1
    fi
fi
echo $$ > "$PIDFILE"

# The green menu's CarPlay switch (ClusterMapPhones): CLUSTERMAP_CARPLAY_MAP=0
# in gal_dualscreen.conf, next to this script, keeps the cluster on the car's
# own map while CarPlay stays connected. Read every second, so the switch
# works with the phone plugged in; no line means on.
CONF=`dirname "$0"`/gal_dualscreen.conf
MAP_WAS=1
carplay_map_on() {
    v=`sed -n 's/^[ 	]*CLUSTERMAP_CARPLAY_MAP[ 	]*=[ 	]*\([01]\)[ 	]*$/\1/p' "$CONF" 2>/dev/null | sed -n '1p'`
    if [ "$v" = 0 ]; then
        [ "$MAP_WAS" = 1 ] && log "CarPlay cluster map switched off in the menu"
        MAP_WAS=0
        return 1
    fi
    [ "$MAP_WAS" = 0 ] && log "CarPlay cluster map switched on in the menu"
    MAP_WAS=1
    return 0
}

player_running() { [ -n "$PLAYER_PID" ] && kill -0 "$PLAYER_PID" 2>/dev/null; }

stop_player() {
    player_running || { PLAYER_PID=; return; }
    log "stopping player $PLAYER_PID ($1)"
    kill -TERM "$PLAYER_PID" 2>/dev/null
    n=0
    # It restores the stock map before it exits; allow it the time.
    while player_running && [ $n -lt 8 ]; do sleep 1; n=`expr $n + 1`; done
    player_running && kill -9 "$PLAYER_PID" 2>/dev/null
    wait "$PLAYER_PID" 2>/dev/null
    PLAYER_PID=
}

cleanup() {
    stop_player "supervisor exit"
    [ "`cat $PIDFILE 2>/dev/null`" = $$ ] && rm -f "$PIDFILE"
}
trap cleanup 0
trap 'exit 0' 1 2 15

log "started for dio_manager $OWNER"
FAILS=0
while kill -0 "$OWNER" 2>/dev/null; do
    CUR=`cat "$STATE" 2>/dev/null`
    if [ "$CUR" = streaming ] && carplay_map_on; then
        if ! player_running; then
            if [ -n "$PLAYER_PID" ]; then
                # It ended on its own while CarPlay still streams. Only a
                # player that dies within 30 s counts towards giving up: one
                # that ran for minutes before the hook reset its stream is
                # not failing, and counting those made the cluster stay on
                # the car's map after the fifth reset of a drive (#10, #43).
                wait "$PLAYER_PID" 2>/dev/null
                PLAYER_PID=
                if [ `expr ${SECONDS%%.*} - $PLAYER_START` -ge 30 ]; then
                    FAILS=0
                fi
                FAILS=`expr $FAILS + 1`
                [ $FAILS -ge 5 ] && { log "player failed $FAILS times; giving up until CarPlay restarts"; break; }
                sleep 2
            fi
            log "CarPlay cluster stream is up; starting player"
            echo "==== stream-player for CarPlay ====" >> "$PLAYER_LOG"
            "$PLAYER" --no-ack "$SOURCE" >> "$PLAYER_LOG" 2>&1 &
            PLAYER_PID=$!
            PLAYER_START=${SECONDS%%.*}
        fi
    else
        carplay_map_on  # logs a menu change even when nothing is streaming
        [ -n "$PLAYER_PID" ] && stop_player "stream state ${CUR:-none}, or switched off in the menu"
        FAILS=0
    fi
    sleep 1
done
log "dio_manager $OWNER is gone"
