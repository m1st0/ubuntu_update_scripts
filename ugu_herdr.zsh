#!/usr/bin/env zsh
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright (c) 2017-2026 Maulik Mistry
#
# Author: Maulik Mistry
# Please share support: https://www.paypal.com/paypalme/m1st0
#                       https://venmo.com/code?user_id=3319592654995456106&created=1753283702
#
# herdr backend helpers. Sourced by ugu.zsh and ugu_dashboard.zsh when UGU is
# run from inside a herdr pane (HERDR_ENV=1) or with UGU_MUX=herdr.
#
# herdr does the multiplexing: one workspace, one tab per worker, plus a
# dashboard tab. These helpers mirror each worker's state file into herdr's
# sidebar (pane report-agent and report-metadata), so the sidebar shows a
# state icon, a label and a percentage for every worker. The state files stay
# the source of truth; nothing here parses terminal text for success.

[[ -n "${UGU_HERDR_LOADED:-}" ]] && return 0
typeset -g UGU_HERDR_LOADED=1

typeset -g UGU_HERDR_BIN="${HERDR_BIN_PATH:-herdr}"
typeset -g UGU_HERDR_WS=""
typeset -gA UGU_HERDR_PANE UGU_HERDR_TAB UGU_HERDR_LAST

ugu_hd() { command "$UGU_HERDR_BIN" "$@" }

# True inside a herdr pane with a usable CLI.
ugu_herdr_available() {
    [[ "${HERDR_ENV:-}" == 1 ]] || return 1
    [[ -x "$UGU_HERDR_BIN" ]] && return 0
    (( $+commands[$UGU_HERDR_BIN] ))
}

# Print one field of a herdr JSON response. Usage: ugu_herdr_json JSON JQ_PATH
ugu_herdr_json() {
    print -r -- "$1" | jq -r "$2 // empty" 2>/dev/null
}

# The workspace, tab and pane ids are written once by the orchestrator, then
# read by the dashboard: STATE_DIR/herdr/{workspace,NAME.tab,NAME.pane}.
ugu_herdr_load_ids() {
    local state_dir="$1" w v
    shift
    [[ -r "$state_dir/herdr/workspace" ]] && read -r UGU_HERDR_WS < "$state_dir/herdr/workspace"
    for w in dashboard "$@"; do
        v=""
        [[ -r "$state_dir/herdr/$w.tab" ]] && read -r v < "$state_dir/herdr/$w.tab"
        UGU_HERDR_TAB[$w]="$v"
        v=""
        [[ -r "$state_dir/herdr/$w.pane" ]] && read -r v < "$state_dir/herdr/$w.pane"
        UGU_HERDR_PANE[$w]="$v"
    done
}

# Mirror one worker into the sidebar. Only calls herdr when something changed.
#   ugu_herdr_report WORKER STATE PCT STAGE MSG [HINT]
# STATE is the UGU state (queued, running, input, done, failed). HINT is 1 when
# the worker's screen looks like it is waiting for a password or y/n answer.
#
# herdr has no failed state, so a failure is reported as "unknown" with the
# label "failed". A finished worker is reported as idle; herdr shows it as
# done until you have looked at it.
ugu_herdr_report() {
    local w="$1" state="$2" pct="$3" stage="$4" msg="${5:-}" hint="${6:-0}"
    local pane="${UGU_HERDR_PANE[$w]:-}" hs idle_label="queued" blocked_label="needs input" sig prev
    [[ -n "$pane" ]] || return 0

    case "$state" in
        running) hs=working
                 [[ "$hint" == 1 ]] && { hs=blocked; blocked_label="may need input"; } ;;
        input)   hs=blocked ;;
        done)    hs=idle; idle_label="done" ;;
        failed)  hs=unknown ;;
        *)       hs=idle ;;
    esac

    sig="$hs|$state|$pct|$stage|$blocked_label"
    [[ "${UGU_HERDR_LAST[$w]:-}" == "$sig" ]] && return 0
    prev="${UGU_HERDR_LAST[$w]:-}"
    UGU_HERDR_LAST[$w]="$sig"

    local -a msg_args=()
    [[ -n "$msg" ]] && msg_args=( --message "$msg" )
    ugu_hd pane report-agent "$pane" --source ugu --agent "ugu-$w" --state "$hs" "${msg_args[@]}" >/dev/null 2>&1
    ugu_hd pane report-metadata "$pane" --source ugu \
        --token "percent=$pct" --token "stage=$stage" \
        --state-label "working=$stage ${pct}%" \
        --state-label "blocked=$blocked_label" \
        --state-label "idle=$idle_label" \
        --state-label "done=done" \
        --state-label "unknown=failed" >/dev/null 2>&1

    # Tell you once when a worker starts needing you, or fails.
    if [[ "$hs" == blocked && "${prev%%|*}" != blocked ]]; then
        ugu_hd notification show "UGU: ${w} needs input" --body "$stage" --sound request >/dev/null 2>&1
    elif [[ "$state" == failed && "${prev%%|*}" != unknown ]]; then
        ugu_hd notification show "UGU: ${w} failed" --body "$msg" --sound request >/dev/null 2>&1
    fi
}

# Show a worker's (or the dashboard's) tab. Only the tab changes: your current
# workspace is left alone, and the blocked state and a toast tell you to look.
ugu_herdr_goto() {
    local id="${UGU_HERDR_TAB[$1]:-}"
    [[ -n "$id" ]] || return 0
    ugu_hd tab focus "$id" >/dev/null 2>&1
}

# Name of the worker (or "dashboard") whose tab is focused in the UGU
# workspace, in REPLY. Empty when it cannot tell.
ugu_herdr_current() {
    local id k
    REPLY=""
    [[ -n "$UGU_HERDR_WS" ]] || return 0
    id="$(ugu_hd tab list --workspace "$UGU_HERDR_WS" 2>/dev/null \
        | jq -r '.result.tabs[]? | select(.focused) | .tab_id' 2>/dev/null)"
    [[ -n "$id" ]] || return 0
    for k in "${(@k)UGU_HERDR_TAB}"; do
        [[ "${UGU_HERDR_TAB[$k]}" == "$id" ]] && { REPLY="$k"; return 0 }
    done
}

# Write STATE_DIR/launch/NAME.zsh, which runs the given command with this
# orchestrator's PATH and settings. pane run types a short, shell-neutral line
# (zsh /path/to/launcher) into the pane, so the pane's own shell never has to
# understand the quoting. REPLY is the launcher path.
#   ugu_herdr_launcher NAME LOGFILE COMMAND [ARG...]
# With LOGFILE set, the command runs under script(1) so its output is also kept
# in a log, as tmux's pipe-pane does. script returns the command's exit status.
ugu_herdr_launcher() {
    local name="$1" log="$2" arg inner
    shift 2
    local -a quoted=()
    for arg in "$@"; do quoted+=( "${(q)arg}" ); done
    inner="${(j: :)quoted}"

    REPLY="$UGU_STATE_DIR/launch/$name.zsh"
    {
        print -r -- '#!/usr/bin/env zsh'
        print -r -- "export PATH=${(q)PATH}"
        print -r -- "export UGU_MUX=herdr UGU_STATE_DIR=${(q)UGU_STATE_DIR}"
        print -r -- "export UGU_ASSUME_YES=${(q)${UGU_ASSUME_YES:-0}}"
        if [[ -n "$log" ]]; then
            print -r -- "script -qfe -c ${(q)inner} ${(q)log}"
        else
            print -r -- "$inner"
        fi
    } > "$REPLY"
}
