#!/usr/bin/env zsh
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright (c) 2017-2026 Maulik Mistry
#
# Author: Maulik Mistry
# Please share support: https://www.paypal.com/paypalme/m1st0
#                       https://venmo.com/code?user_id=3319592654995456106&created=1753283702
#
# Shared library for every UGU script. Safe to source more than once.
#
# Workers use ugu_run_worker, which bootstraps everything a worker needs, so a
# worker behaves the same whether the orchestrator launched it inside tmux or
# you ran it by hand (./ugu_system.zsh).


(( ${+UGU_COMMON_LOADED} )) && return 0
typeset -g UGU_COMMON_LOADED=1

setopt NO_UNSET PIPE_FAIL

zmodload zsh/parameter zsh/datetime || {
    print -u2 -r -- "The zsh/datetime module is required."
    return 1
}

UGU_SCRIPT_DIR="${${(%):-%x}:A:h}"
UGU_VENDOR_TPUT="$UGU_SCRIPT_DIR/vendor/tput_shell_colorize/tput_shell_colorize.sh"
if [[ ! -r "$UGU_VENDOR_TPUT" ]]; then
    print -u2 -r -- "Missing vendor/tput_shell_colorize/tput_shell_colorize.sh"
    return 1
fi
source "$UGU_VENDOR_TPUT"
setopt NO_UNSET PIPE_FAIL

# The vendor file provides messenger_std, messenger_end, messenger_std_inline,
# linefeed, the color slots (RED GREEN ... WHITE, BOLD, RESET) and the semantic
# names COLOR_SUCCESS COLOR_WARNING COLOR_ERROR COLOR_INFO COLOR_RESET. Prefer
# the semantic names: terminal themes remap the slot names. These defaults
# keep UGU working with an older vendor file that lacks the semantic names.
: "${COLOR_SUCCESS=${GREEN}}" "${COLOR_WARNING=${YELLOW}}" "${COLOR_ERROR=${RED}}" "${COLOR_INFO=${CYAN}}" "${COLOR_RESET=${RESET}}"

# Defaults so these are always set under NO_UNSET.
typeset -gi UGU_LIVE_OPEN=0 UGU_LAST_PCT=0 UGU_STANDALONE=0
typeset -g UGU_LAST_STAGE="" UGU_KEEPALIVE_PID="" UGU_WORKER_ID="${UGU_WORKER_ID:-}"

typeset -ga UGU_RAMP=( 27 33 39 45 51 50 49 48 47 46 )
typeset -ga UGU_SPINNER=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )

ugu_require_commands() {
    local command_name
    for command_name in "$@"; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            messenger_end "Required command not found: $command_name"
            return 1
        fi
    done
}

# ---------------------------------------------------------------------------
# Small formatting helpers. They return their result in REPLY (no subshells,
# so they are cheap enough to call many times per animation frame).
# ---------------------------------------------------------------------------

ugu_clean_field() {
    REPLY="${1//$'\n'/ }"
    REPLY="${REPLY//$'\r'/ }"
    REPLY="${REPLY//|/:}"
}

ugu_fmt_time() {
    local -i s=$1
    (( s < 0 )) && s=0
    if (( s >= 3600 )); then
        printf -v REPLY '%d:%02d:%02d' $(( s / 3600 )) $(( s % 3600 / 60 )) $(( s % 60 ))
    else
        printf -v REPLY '%02d:%02d' $(( s / 60 )) $(( s % 60 ))
    fi
}

ugu_human_bytes() {
    local -F1 v=$1
    local -a units=( B KB MB GB TB )
    local -i i=1
    while (( v >= 1024 && i < ${#units} )); do
        (( v /= 1024 ))
        (( i += 1 ))
    done
    REPLY="${v} ${units[i]}"
}

# ugu_bar WIDTH PERCENT FRAME STATE
# STATE: running (blue to green gradient with a moving highlight), done,
# failed, input. FRAME drives the highlight sweep.
ugu_bar() {
    local -i width=$1 pct=$2 frame=${3:-0}
    local state="${4:-running}"
    local -i filled=0 i=0 sweep=0 idx=0 ramp_n=${#UGU_RAMP}
    local out="" color
    (( pct < 0 )) && pct=0
    (( pct > 100 )) && pct=100
    filled=$(( pct * width / 100 ))
    (( pct > 0 && filled < 1 )) && filled=1
    sweep=$(( frame % (width + 10) - 3 ))
    for (( i = 0; i < width; i++ )); do
        if (( i < filled )); then
            case "$state" in
                done)   color=42 ;;
                failed) color=196 ;;
                input)  color=214 ;;
                *)
                    idx=$(( i * ramp_n / width + 1 ))
                    color="${UGU_RAMP[idx]}"
                    (( i - sweep >= -1 && i - sweep <= 1 )) && color=231
                    ;;
            esac
            out+=$'\e[38;5;'"${color}"$'m█'
        else
            out+=$'\e[38;5;238m░'
        fi
    done
    REPLY="${out}"$'\e[0m'
}

# ---------------------------------------------------------------------------
# State protocol. One tiny file per worker, replaced atomically:
#   state|percent|stage|message|worker_start_epoch|updated_epoch
# state is one of: running, input, done, failed. A missing file means queued.
# Terminal output is never parsed to decide success or progress.
# ---------------------------------------------------------------------------

ugu_state_write() {
    local worker="$1" state="$2" pct="$3" stage="$4" msg="$5"
    local dir="${UGU_STATE_DIR:-}"
    [[ -n "$dir" && -d "$dir" ]] || return 1
    local file="$dir/$worker.state"
    local tmp="$file.tmp.$$"
    print -r -- "$state|$pct|$stage|$msg|${UGU_WORKER_START:-$EPOCHSECONDS}|$EPOCHSECONDS" > "$tmp" || return 1
    mv -f -- "$tmp" "$file"
}

# Activity feed shown by the dashboard and kept for the final report.
ugu_note() {
    local worker="$1" text="$2"
    [[ -n "${UGU_STATE_DIR:-}" && -d "$UGU_STATE_DIR" ]] || return 0
    ugu_clean_field "$text"
    print -r -- "$EPOCHSECONDS|$worker|$REPLY" >> "$UGU_STATE_DIR/events.log"
}

# Print one progress line into the worker's own terminal.
ugu_tty_line() {
    local pct="$1" stage="$2" msg="$3" live="${4:-}"
    if [[ ! -t 1 ]]; then
        print -r -- "[${pct}%] $stage: $msg"
        return 0
    fi
    local -i cols=${COLUMNS:-100} room=0
    ugu_bar 24 "$pct" 0 running
    local bar="$REPLY"
    room=$(( cols - 24 - 1 - 4 - 2 - ${#stage} - 2 ))
    (( room < 0 )) && room=0
    (( ${#msg} > room )) && msg="${msg[1,room]}"
    local line
    line="${bar} ${(l:3:)pct}%  ${BOLD}${COLOR_INFO}${stage}${COLOR_RESET}  "$'\e[38;5;245m'"${msg}"$'\e[0m'
    if [[ -n "$live" ]]; then
        print -rn -- $'\r\e[K'"$line"
        UGU_LIVE_OPEN=1
    else
        (( UGU_LIVE_OPEN )) && { linefeed; UGU_LIVE_OPEN=0 }
        print -r -- "$line"
    fi
}

# ugu_progress WORKER PERCENT STAGE MESSAGE [live]
# "live" redraws the same terminal line (used for download progress).
ugu_progress() {
    local worker="$1" pct="$2" stage="$3" msg="${4:-}" live="${5:-}"
    [[ "$pct" == <-> ]] || pct=0
    (( pct > 100 )) && pct=100
    ugu_clean_field "$stage"; stage="$REPLY"
    ugu_clean_field "$msg"; msg="$REPLY"

    ugu_state_write "$worker" running "$pct" "$stage" "$msg" || return 1
    UGU_LAST_PCT="$pct"
    if [[ "$stage" != "$UGU_LAST_STAGE" ]]; then
        ugu_note "$worker" "$stage: $msg"
        UGU_LAST_STAGE="$stage"
    fi
    ugu_tty_line "$pct" "$stage" "$msg" "$live"
}

# Final state. Called by the runner (or by ugu_run_worker when standalone).
ugu_done() {
    local worker="$1" rc="$2"
    local state="running" pct="0" stage="Starting" msg="" rest=""
    local file="${UGU_STATE_DIR:-/nonexistent}/$worker.state"
    [[ -r "$file" ]] && IFS='|' read -r state pct stage msg rest < "$file"
    [[ "$pct" == <-> ]] || pct=0
    if (( rc == 0 )); then
        if (( pct != 100 )); then
            stage="Complete"
            msg="Worker finished"
        fi
        ugu_state_write "$worker" done 100 "$stage" "$msg"
        ugu_note "$worker" "finished ok"
    else
        ugu_state_write "$worker" failed "$pct" "Failed" "$stage: exit status $rc"
        ugu_note "$worker" "FAILED during '$stage' (exit $rc)"
    fi
}

# ---------------------------------------------------------------------------
# sudo. Sudo timestamps are normally tied to the terminal. Every tmux window
# is its own pty, so a password typed in the orchestrator's terminal does not
# carry over. A worker that needs root therefore authenticates for itself, in
# its own window, and keeps its own timestamp fresh.
# ---------------------------------------------------------------------------

ugu_sudo_keepalive() {
    [[ -n "${UGU_KEEPALIVE_PID:-}" ]] && return 0
    ( while sleep 45; do sudo -n -v 2>/dev/null || exit 0; done ) >/dev/null 2>&1 &
    typeset -g UGU_KEEPALIVE_PID=$!
}

ugu_sudo_keepalive_stop() {
    if [[ -n "${UGU_KEEPALIVE_PID:-}" ]]; then
        kill "$UGU_KEEPALIVE_PID" 2>/dev/null
        UGU_KEEPALIVE_PID=""
    fi
}

ugu_require_sudo() {
    if ! command -v sudo >/dev/null 2>&1; then
        messenger_end "sudo is not installed."
        return 1
    fi
    if ! sudo -n -v 2>/dev/null; then
        # Unattended (cron, headless, no terminal): nobody can type a password,
        # so fail fast instead of waiting for sudo's password timeout.
        if [[ "${UGU_NONINTERACTIVE:-0}" == 1 || ! -t 0 ]]; then
            messenger_end "sudo needs a password but this run is unattended."
            messenger_end "Allow passwordless sudo for these commands, or run UGU interactively."
            return 1
        fi
        # The dashboard sees the "input" state and jumps to this window.
        ugu_state_write "$UGU_WORKER_ID" input "$UGU_LAST_PCT" "Needs sudo" "Enter your password in this window"
        ugu_note "$UGU_WORKER_ID" "waiting for sudo password"
        (( UGU_LIVE_OPEN )) && { linefeed; UGU_LIVE_OPEN=0 }
        messenger_std "sudo authentication is required for the $UGU_WORKER_ID worker."
        if ! sudo -v; then
            messenger_end "Sudo authentication was not successful."
            return 1
        fi
        ugu_state_write "$UGU_WORKER_ID" running "$UGU_LAST_PCT" "Authenticated" "sudo is ready"
    fi
    ugu_sudo_keepalive
    return 0
}

# ---------------------------------------------------------------------------
# Download with real progress. curl runs in the background and the partial
# file size is compared with the Content-Length from a HEAD request. File size
# is reliable; the terminal output of curl is not parsed.
# ugu_download URL OUTPUT LABEL PERCENT_START PERCENT_END
# ---------------------------------------------------------------------------

ugu_download() {
    local url="$1" out="$2" label="$3"
    local -i p0=$4 p1=$5 total=0 size=0 last_size=0 pct=0 pid=0 rc=1
    local -F now=0 last_t=0 speed=0
    local hdr cur tot spd

    hdr="$(curl -fsSIL --connect-timeout 10 --max-time 20 -- "$url" 2>/dev/null | tr -d '\r')" || hdr=""
    total="$(print -r -- "$hdr" | awk 'tolower($1)=="content-length:" { v=$2 } END { print v+0 }')" || total=0

    : > "$out" || return 1
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 -o "$out" -- "$url" &
    pid=$!
    last_t=$EPOCHREALTIME
    {
        while kill -0 "$pid" 2>/dev/null; do
            size="$(stat -c %s -- "$out" 2>/dev/null)" || size=0
            now=$EPOCHREALTIME
            if (( now - last_t >= 0.5 )); then
                speed=$(( (size - last_size) / (now - last_t) ))
                last_size=$size
                last_t=$now
            fi
            pct=$p0
            if (( total > 0 )); then
                pct=$(( p0 + (p1 - p0) * size / total ))
                (( pct > p1 )) && pct=$p1
            fi
            ugu_human_bytes $size; cur="$REPLY"
            ugu_human_bytes $speed; spd="$REPLY"
            if (( total > 0 )); then
                ugu_human_bytes $total; tot="$REPLY"
                ugu_progress "$UGU_WORKER_ID" "$pct" "Downloading" "$label  $cur of $tot  ${spd}/s" live
            else
                ugu_progress "$UGU_WORKER_ID" "$pct" "Downloading" "$label  $cur  ${spd}/s" live
            fi
            sleep 0.25
        done
        wait "$pid"
        rc=$?
        pid=0
    } always {
        (( pid > 0 )) && kill "$pid" 2>/dev/null
    }

    if (( rc == 0 )); then
        ugu_progress "$UGU_WORKER_ID" "$p1" "Downloaded" "$label"
    fi
    return $rc
}

# ---------------------------------------------------------------------------
# Worker lifecycle
# ---------------------------------------------------------------------------

ugu_worker_init() {
    typeset -g UGU_WORKER_ID="${UGU_WORKER_ID:-$1}"
    typeset -gx UGU_WORKER_START="${UGU_WORKER_START:-$EPOCHSECONDS}"
    typeset -gi UGU_STANDALONE=0 UGU_LIVE_OPEN=0 UGU_LAST_PCT=0
    typeset -g UGU_LAST_STAGE="" UGU_KEEPALIVE_PID=""

    if [[ -z "${UGU_STATE_DIR:-}" ]]; then
        # Run by hand: create a private scratch state directory.
        local base="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
        [[ -d "$base" && -w "$base" ]] || base="/tmp"
        typeset -gx UGU_STATE_DIR
        UGU_STATE_DIR="$(mktemp -d "$base/ugu-${UID}-${UGU_WORKER_ID}.XXXXXX")" || return 1
        UGU_STANDALONE=1
        mkdir -p -m 700 "$UGU_STATE_DIR/results" "$UGU_STATE_DIR/logs"
    fi
    return 0
}

# ugu_run_worker NAME MAIN_FUNCTION
ugu_run_worker() {
    local name="$1" main="$2"
    local -i rc=1
    ugu_worker_init "$name" || return 1
    if (( UGU_STANDALONE )); then
        messenger_std "UGU $name worker (standalone run)"
    fi
    {
        "$main"
        rc=$?
    } always {
        ugu_sudo_keepalive_stop
        (( UGU_LIVE_OPEN )) && { linefeed; UGU_LIVE_OPEN=0 }
        if (( UGU_STANDALONE )); then
            ugu_done "$UGU_WORKER_ID" "$rc"
            if [[ "$UGU_STATE_DIR" == */ugu-${UID}-${UGU_WORKER_ID}.* ]]; then
                rm -rf -- "$UGU_STATE_DIR"
            fi
        fi
    }
    return $rc
}
