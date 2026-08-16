#!/bin/zsh
set -euo pipefail

APP="${1:?usage: Scripts/measure_idle.sh /path/to/QuotaBeacon.app [seconds]}"
DURATION="${2:-600}"
OUT="${MEASURE_OUTPUT:-/tmp/quotabeacon-idle-$(date +%Y%m%d-%H%M%S).csv}"

open -n "$APP"
sleep 3
PID="$(pgrep -nx QuotaBeacon)"
print 'timestamp,cpu_percent,rss_kib' > "$OUT"
for ((i = 0; i < DURATION; i += 5)); do
  ps -p "$PID" -o lstart=,%cpu=,rss= | awk -v now="$(date -Iseconds)" '{print now "," $(NF-1) "," $NF}' >> "$OUT"
  sleep 5
done
kill -TERM "$PID"
print "$OUT"
