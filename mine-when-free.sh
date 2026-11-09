#!/usr/bin/env bash
# mine-when-free.sh — run gbxminer only after the GPU has been idle for a while.
#
#   ./mine-when-free.sh [gbxminer args...]
#   e.g. ./mine-when-free.sh -a kheavyhash -o stratum+tcp://POOL:PORT -u WALLET.gh200
#
# Behaviour
#   1. Waits until GPU utilisation stays <= IDLE_UTIL % for IDLE_SECS seconds.
#   2. Starts gbxminer with the given args.
#   3. While mining, if any *other* process starts using the GPU, the miner is
#      stopped and we go back to step 1 (training jobs always win).
#   4. Ctrl+C at any time stops the miner and exits.
#
# Env overrides: IDLE_SECS (600), IDLE_UTIL (5), POLL (10), GPU (0), MINER (./gbxminer)
set -uo pipefail
cd "$(dirname "$0")"

IDLE_SECS="${IDLE_SECS:-600}"
IDLE_UTIL="${IDLE_UTIL:-5}"
POLL="${POLL:-10}"
GPU="${GPU:-0}"
MINER="${MINER:-./gbxminer}"
MINER_PID=""

log() { echo "[$(date '+%F %T')] $*"; }

stop_miner() {
    if [[ -n "$MINER_PID" ]] && kill -0 "$MINER_PID" 2>/dev/null; then
        log "stopping miner (pid $MINER_PID)"
        kill -INT "$MINER_PID" 2>/dev/null
        for _ in {1..10}; do kill -0 "$MINER_PID" 2>/dev/null || break; sleep 1; done
        kill -KILL "$MINER_PID" 2>/dev/null
        wait "$MINER_PID" 2>/dev/null
    fi
    MINER_PID=""
}
trap 'echo; stop_miner; log "interrupted, bye"; exit 0' INT TERM

gpu_util() { nvidia-smi -i "$GPU" --query-gpu=utilization.gpu --format=csv,noheader,nounits | tr -d ' '; }
gpu_pids() { nvidia-smi -i "$GPU" --query-compute-apps=pid --format=csv,noheader,nounits | tr -d ' ' | sort -u; }

wait_idle() {
    local idle=0
    log "waiting for GPU $GPU idle (<= ${IDLE_UTIL}% for ${IDLE_SECS}s)"
    while (( idle < IDLE_SECS )); do
        local u; u="$(gpu_util)"
        if (( u <= IDLE_UTIL )); then idle=$((idle + POLL)); else
            (( idle > 0 )) && log "GPU busy (${u}%), reset idle timer"; idle=0; fi
        sleep "$POLL"
    done
    log "GPU idle for ${IDLE_SECS}s"
}

while true; do
    wait_idle
    baseline="$(gpu_pids)"          # processes already resident (idle) are tolerated
    "$MINER" "$@" &
    MINER_PID=$!
    log "miner started (pid $MINER_PID)"
    while kill -0 "$MINER_PID" 2>/dev/null; do
        sleep "$POLL"
        new="$(comm -13 <(echo "$baseline") <(gpu_pids) | grep -vx "$MINER_PID" | grep -v '^$' || true)"
        if [[ -n "$new" ]]; then
            log "new GPU process(es) detected: $(echo $new) — yielding GPU"
            stop_miner
            break
        fi
    done
    [[ -n "$MINER_PID" ]] && { wait "$MINER_PID"; log "miner exited ($?)"; MINER_PID=""; }
    sleep "$POLL"
done
