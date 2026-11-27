#!/usr/bin/env bash
# Sends a job to the editor's job runner and waits for its result (JSON on stdout): job.sh JOB.py [TIMEOUT_S]
# Local by default; with UE_SSH_HOST set, the jobs folder is on that host (short ssh calls, retried).
set -uo pipefail
job=$1; t=${2:-600}; name=$(basename "$job" .py)
D=${UE_JOBS_DIR:?set UE_JOBS_DIR to the project Saved/Jobs folder}
if [ -n "${UE_SSH_HOST:-}" ]; then
  S="ssh -o BatchMode=yes -o ConnectTimeout=20 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 $UE_SSH_HOST"
  put() { scp -q -o ConnectTimeout=20 "$1" "$UE_SSH_HOST:$2"; }
else
  S="bash -c"; put() { cp "$1" "$2"; }
fi
try() { for i in 1 2 3 4 5 6; do "$@" && return 0; sleep 5; done; return 1; }
try $S "mkdir -p $D/done && rm -f $D/done/$name.json" || { echo "cannot reach the jobs folder"; exit 1; }
try put "$job" "$D/.$name.py" || exit 1
try $S "mv $D/.$name.py $D/$name.py" || exit 1
end=$(( $(date +%s) + t ))
while [ "$(date +%s)" -lt "$end" ]; do
  out=$($S "cat $D/done/$name.json 2>/dev/null" 2>/dev/null) && [ -n "$out" ] && { printf '%s\n' "$out"; exit 0; }
  sleep 3
done
echo TIMEOUT; $S "cat $D/server.json"; exit 1
