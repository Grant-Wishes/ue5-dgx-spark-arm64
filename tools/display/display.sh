#!/usr/bin/env bash
# A display for the Unreal editor on a headless DGX Spark, without root (26 Nov): Xorg on the GB10 with no monitor
# (xorg-headless.conf), on a seat of its own so it needs no virtual terminal, and the NVIDIA X driver from its own folder.
# Usage: display.sh start|stop|status|shot FILE.png|record FILE.mp4 SECONDS
#   DISPLAY_NUM (default 3), LOG_DIR (default /tmp/ue-display-$USER)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
n=${DISPLAY_NUM:-3}
logs=${LOG_DIR:-/tmp/ue-display-$USER}
mkdir -p "$logs"
pidf="$logs/Xorg.$n.pid"
alive() { [ -f "$pidf" ] && kill -0 "$(cat "$pidf")" 2>/dev/null; }
case "${1:-status}" in
  start)
    alive && { echo "display :$n already running (pid $(cat "$pidf"))"; exit 0; }
    setsid /usr/lib/xorg/Xorg ":$n" -seat "seat$n-ue" -config "$here/xorg-headless.conf" -nolisten tcp -noreset \
      -modulepath /usr/lib/aarch64-linux-gnu/nvidia/xorg,/usr/lib/xorg/modules -logfile "$logs/Xorg.$n.log" \
      > "$logs/Xorg.$n.out" 2>&1 < /dev/null &
    echo $! > "$pidf"
    for _ in $(seq 30); do DISPLAY=":$n" xdpyinfo > /dev/null 2>&1 && break; sleep 0.5; done
    DISPLAY=":$n" xdpyinfo > /dev/null 2>&1 || { echo "Xorg did not start: $logs/Xorg.$n.log" >&2; exit 1; }
    echo "display :$n ready ($(DISPLAY=":$n" xdpyinfo | awk '/dimensions/ {print $2}'))" ;;
  stop)
    alive && kill "$(cat "$pidf")" && echo "display :$n stopped" || echo "display :$n not running"
    rm -f "$pidf" ;;
  status)
    alive && echo "display :$n running (pid $(cat "$pidf"))" || echo "display :$n not running" ;;
  shot)   # one frame of the whole screen
    ffmpeg -loglevel error -y -f x11grab -video_size 1920x1080 -i ":$n" -frames:v 1 "$2" ;;
  record) # the whole screen, NVENC H.264 (the GB10's encoder; the CPU stays free for the editor)
    ffmpeg -loglevel error -y -f x11grab -framerate 30 -video_size 1920x1080 -i ":$n" -t "$3" \
      -c:v h264_nvenc -preset p5 -cq 21 -pix_fmt yuv420p "$2" ;;
  *) echo "usage: display.sh start|stop|status|shot FILE|record FILE SECONDS" >&2; exit 2 ;;
esac
