#!/usr/bin/env zsh
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright (c) 2017-2026 Maulik Mistry
#
# Author: Maulik Mistry
# Please share support: https://www.paypal.com/paypalme/m1st0
#                       https://venmo.com/code?user_id=3319592654995456106&created=1753283702
#
# Live dashboard (tmux window 0). Usage: ugu_dashboard.zsh STATE_DIR SESSION WORKER...
#
# Rendering is native ANSI: each frame is built in memory and written once,
# starting from the cursor home position with no screen clear. That is what
# removes the flicker; the old version cleared the screen and ran `gum style`
# about twenty times per frame. Gum is still used for the final summary.
#
# Keys: 1-9 jump to a worker window. When everything has finished, q or Enter
# closes UGU.


setopt NO_UNSET
source "${0:A:h}/ugu_common.zsh" || exit 1

state_dir="$1"
session="$2"
shift 2
typeset -a workers
workers=( "$@" )
integer n_workers=${#workers}

esc=$'\e'
integer rows=40 cols=100 frame=0 need_clear=1 all_done=0 finish_epoch=0 start_epoch=$EPOCHSECONDS
typeset -A want_map last_icon tail_line waiting_hint
typeset focus_worker=""

[[ -r "$state_dir/start" ]] && start_epoch="$(<"$state_dir/start")"

read_size() {
    local sz
    sz="$(stty size 2>/dev/null)" || return 0
    [[ "$sz" == <->\ <-> ]] || return 0
    rows="${sz% *}"
    cols="${sz#* }"
    need_clear=1
}
TRAPWINCH() { read_size }
read_size

enter_ui() { print -rn -- "${esc}[?1049h${esc}[?25l${esc}[2J" }
leave_ui() { print -rn -- "${esc}[?25h${esc}[?1049l" }
trap leave_ui EXIT
enter_ui

# Title colors rotate slowly: the title shimmers.
typeset -a title_colors=( 213 177 141 105 69 39 45 51 )
title_text="UGU  Ubuntu Grab Updates"

sp() {
    local -i n=$1
    (( n < 0 )) && n=0
    printf -v REPLY '%*s' $n ''
}

# Refresh the last visible line of each worker's terminal (about twice a
# second). This is a display hint only. Success and progress come from the
# state files, never from this text.
refresh_tails() {
    local w text l low
    local -a lines
    local -i i
    for w in "${workers[@]}"; do
        text="$(tmux capture-pane -p -J -t "$session:$w" 2>/dev/null)" || text=""
        lines=( "${(@f)text}" )
        tail_line[$w]=""
        waiting_hint[$w]=0
        for (( i = ${#lines}; i >= 1; i-- )); do
            l="${lines[i]//[^[:print:]]/}"
            [[ -z "${l//[[:space:]]/}" ]] && continue
            low="${(L)l}"
            if [[ "$low" =~ '(password.*:|\[y[/|]n\]|\[yes/no\]|\(y/n\))' ]]; then
                waiting_hint[$w]=1
            fi
            [[ "$l" == [█░]* || "$l" == "Pane is dead"* ]] && continue
            tail_line[$w]="$l"
            break
        done
    done
}

set_window_icon() {
    local w="$1" icon="$2" color="$3"
    [[ "${last_icon[$w]:-}" == "$icon$color" ]] && return 0
    last_icon[$w]="$icon$color"
    tmux set-option -w -t "$session:$w" @ugu_icon "$icon " 2>/dev/null
    tmux set-option -w -t "$session:$w" @ugu_color "colour$color" 2>/dev/null
}

render() {
    local w l state pct stage msg wstart wupd extra icon icolor stage_color name_color
    local bar timecell pctcell line sep padL padR
    local -i i idx want=0 total=0 complete=0 active=0 failed=0 waiting=0 overall=0
    local -i name_w=0 stage_w=16 bar_w W=cols el=0 mode=2 used=0 room=0
    local -a L events
    typeset -a st_state st_pct st_stage st_msg st_start st_upd

    (( W > 112 )) && W=112
    for w in "${workers[@]}"; do (( ${#w} > name_w )) && name_w=${#w}; done

    # ---- read state ------------------------------------------------------
    for w in "${workers[@]}"; do
        state="queued"; pct=0; stage="Queued"; msg="Waiting for launch"; wstart=0; wupd=0; extra=""
        if [[ -r "$state_dir/$w.state" ]]; then
            IFS='|' read -r state pct stage msg wstart wupd < "$state_dir/$w.state" || true
        fi
        [[ "$pct" == <-> ]] || pct=0
        st_state+=( "$state" ); st_pct+=( "$pct" ); st_stage+=( "$stage" )
        st_msg+=( "$msg" ); st_start+=( "${wstart:-0}" ); st_upd+=( "${wupd:-0}" )
        case "$state" in
            done)   (( complete += 1 )); (( total += 100 )) ;;
            failed) (( complete += 1 )); (( failed += 1 )); (( total += 100 )) ;;
            input)  (( active += 1 )); (( waiting += 1 )); (( total += pct )) ;;
            running)
                (( active += 1 )); (( total += pct ))
                (( ${waiting_hint[$w]:-0} )) && (( waiting += 1 ))
                ;;
            *) ;;
        esac
    done
    (( n_workers > 0 )) && overall=$(( total / n_workers ))
    (( complete == n_workers )) && all_done=1

    # ---- layout mode: 2 full, 1 with messages, 0 one line per worker -------
    local -i full_need=$(( 12 + 3 * n_workers ))
    local -i mid_need=$(( 7 + 2 * n_workers ))
    (( rows >= full_need )) && mode=2 || { (( rows >= mid_need )) && mode=1 || mode=0 }

    bar_w=$(( W - (2 + 1 + 2 + name_w + 2 + stage_w + 2 + 2 + 4 + 2 + 7) ))
    (( bar_w < 8 )) && bar_w=8
    (( bar_w > 36 )) && bar_w=36

    # ---- header ----------------------------------------------------------
    line="  "
    for (( i = 1; i <= ${#title_text}; i++ )); do
        idx=$(( (i + frame / 3) % ${#title_colors} + 1 ))
        line+="${esc}[1;38;5;${title_colors[idx]}m${title_text[i]}"
    done
    line+="${esc}[0m"
    if (( all_done && finish_epoch == 0 )); then finish_epoch=$EPOCHSECONDS; fi
    if (( all_done )); then
        ugu_fmt_time $(( finish_epoch - start_epoch ))
    else
        ugu_fmt_time $(( EPOCHSECONDS - start_epoch ))
    fi
    local etxt="elapsed $REPLY"
    sp $(( W - 2 - ${#title_text} - ${#etxt} - 2 ))
    line+="$REPLY${esc}[38;5;245m${etxt}${esc}[0m"
    L+=( "$line" )
    local empty="" rule=""
    local -i rule_w=$(( W - 4 ))
    rule="${(l:$rule_w::─:)empty}"
    L+=( "  ${esc}[38;5;240m${rule}${esc}[0m" )

    # ---- overall ----------------------------------------------------------
    local ostate="running"
    (( all_done )) && { (( failed )) && ostate="failed" || ostate="done" }
    (( waiting > 0 && all_done == 0 )) && ostate="input"
    ugu_bar $(( bar_w + 10 )) $overall $frame $ostate; bar="$REPLY"
    line="  ${esc}[1;38;5;255mOverall${esc}[0m  ${bar} ${esc}[1m${(l:3:)overall}%${esc}[0m"
    L+=( "$line" )
    line="  ${esc}[38;5;46m${complete}/${n_workers} done${esc}[0m"
    line+="  ${esc}[38;5;245m|${esc}[0m  ${esc}[38;5;39m${active} running${esc}[0m"
    (( waiting > 0 )) && line+="  ${esc}[38;5;245m|${esc}[0m  ${esc}[1;38;5;214m${waiting} need input${esc}[0m"
    (( failed > 0 )) && line+="  ${esc}[38;5;245m|${esc}[0m  ${esc}[1;38;5;196m${failed} failed${esc}[0m"
    L+=( "$line" "" )

    # ---- workers ----------------------------------------------------------
    for (( i = 1; i <= n_workers; i++ )); do
        w="${workers[i]}"
        state="${st_state[i]}"; pct="${st_pct[i]}"; stage="${st_stage[i]}"; msg="${st_msg[i]}"
        el=0
        case "$state" in
            done)    icon="✓"; icolor=46;  stage_color=46;  name_color=255
                     el=$(( st_upd[i] - st_start[i] )) ;;
            failed)  icon="✗"; icolor=196; stage_color=203; name_color=255
                     el=$(( st_upd[i] - st_start[i] )) ;;
            input)   icon=$(( frame / 4 % 2 )); (( icon )) && icon="◆" || icon="◇"
                     icolor=214; stage_color=214; name_color=255
                     el=$(( EPOCHSECONDS - st_start[i] )) ;;
            running) icon="${UGU_SPINNER[frame % ${#UGU_SPINNER} + 1]}"; icolor=39; stage_color=111; name_color=255
                     el=$(( EPOCHSECONDS - st_start[i] ))
                     if (( ${waiting_hint[$w]:-0} )); then
                         icon="◆"; icolor=214; stage_color=214
                         msg="Waiting for input. Press ${i} to answer in this worker's terminal."
                     fi ;;
            *)       icon="○"; icolor=240; stage_color=240; name_color=244; pct=0 ;;
        esac

        if [[ "$state" == running || "$state" == input || "$state" == done || "$state" == failed ]]; then
            ugu_fmt_time $el; timecell="$REPLY"
        else
            timecell="     "
        fi
        local bstate="$state"
        [[ "$state" == running ]] && (( ${waiting_hint[$w]:-0} )) && bstate="input"
        [[ "$state" == queued ]] && bstate="queued"
        ugu_bar $bar_w $pct $frame "$bstate"; bar="$REPLY"
        [[ "$state" == input ]] && stage="Needs sudo"

        pctcell="${(l:3:)pct}%"
        line="  ${esc}[1;38;5;${icolor}m${icon}${esc}[0m  "
        line+="${esc}[1;38;5;${name_color}m${(r:$name_w:)${(C)w}}${esc}[0m  "
        line+="${esc}[38;5;${stage_color}m${(r:$stage_w:)${stage[1,stage_w]}}${esc}[0m  "
        line+="${bar}  ${esc}[1m${pctcell}${esc}[0m  ${esc}[38;5;245m${timecell}${esc}[0m"
        L+=( "$line" )

        if (( mode >= 1 )); then
            room=$(( W - 8 ))
            (( ${#msg} > room )) && msg="${msg[1,room]}"
            L+=( "      ${esc}[38;5;240m└${esc}[0m ${esc}[38;5;250m${msg}${esc}[0m" )
        fi
        if (( mode >= 2 )); then
            l="${tail_line[$w]:-}"
            room=$(( W - 8 ))
            (( ${#l} > room )) && l="${l[1,room]}"
            L+=( "      ${esc}[38;5;238m│ ${l}${esc}[0m" )
        fi
    done

    # ---- activity feed ----------------------------------------------------
    if (( mode >= 2 )) && [[ -r "$state_dir/events.log" ]]; then
        local ts ew etext tsfmt
        events=( "${(@f)$(<"$state_dir/events.log")}" )
        local -i feed=$(( rows - ${#L} - 4 ))
        (( feed > 6 )) && feed=6
        if (( feed > 0 && ${#events} > 0 )); then
            L+=( "" "  ${esc}[1;38;5;245mActivity${esc}[0m" )
            for line in "${(@)events[-feed,-1]}"; do
                IFS='|' read -r ts ew etext <<< "$line"
                [[ "$ts" == <-> ]] || continue
                strftime -s tsfmt '%H:%M:%S' "$ts"
                room=$(( W - 4 - 8 - 2 - name_w - 2 ))
                (( ${#etext} > room )) && etext="${etext[1,room]}"
                L+=( "  ${esc}[38;5;240m${tsfmt}${esc}[0m  ${esc}[38;5;111m${(r:$name_w:)ew}${esc}[0m  ${esc}[38;5;250m${etext}${esc}[0m" )
            done
        fi
    fi

    # ---- footer -----------------------------------------------------------
    L+=( "" )
    if (( all_done )); then
        if (( failed == 0 )); then
            L+=( "  ${BOLD}${COLOR_SUCCESS}All workers completed successfully.${COLOR_RESET}" )
        else
            L+=( "  ${BOLD}${COLOR_ERROR}${failed} worker(s) failed.${COLOR_RESET} ${esc}[38;5;250mPress the worker's number to read its terminal.${esc}[0m" )
        fi
        L+=( "  ${esc}[38;5;245mPress ${esc}[1mq${esc}[0m${esc}[38;5;245m or ${esc}[1mEnter${esc}[0m${esc}[38;5;245m to close UGU and see the summary. Keys 1-${n_workers} open a worker.${esc}[0m" )
    else
        L+=( "  ${esc}[38;5;245mKeys 1-${n_workers} (or Ctrl-b then a number) open a worker terminal. Ctrl-b 0 returns here.${esc}[0m" )
    fi

    # ---- paint: one write, home position, no screen clear -----------------
    local out="${esc}[H"
    (( need_clear )) && { out+="${esc}[2J"; need_clear=0 }
    local -i last=${#L}
    (( last > rows )) && last=$rows
    for (( i = 1; i <= last; i++ )); do
        out+="${L[i]}${esc}[K"
        (( i < last )) && out+=$'\n'
    done
    out+="${esc}[J"
    print -rn -- "$out"

    # ---- window icons and sudo focus --------------------------------------
    for (( i = 1; i <= n_workers; i++ )); do
        w="${workers[i]}"
        case "${st_state[i]}" in
            done)    set_window_icon "$w" "✓" 46 ;;
            failed)  set_window_icon "$w" "✗" 196 ;;
            input)   set_window_icon "$w" "◆" 214 ;;
            running)
                if (( ${waiting_hint[$w]:-0} )); then
                    set_window_icon "$w" "◆" 214
                else
                    set_window_icon "$w" "●" 39
                fi
                ;;
            *)       set_window_icon "$w" "○" 245 ;;
        esac
        # A worker needs you when it says so (state "input", the first sudo
        # prompt) or when its screen shows a password or y/n prompt (any later
        # prompt). Either way, bring that window forward once.
        want=0
        [[ "${st_state[i]}" == input ]] && want=1
        [[ "${st_state[i]}" == running ]] && (( ${waiting_hint[$w]:-0} )) && want=1
        want_map[$w]=$want
    done

    # One window is brought forward at a time. When its prompt is answered,
    # go to the next worker that is waiting, or back to the dashboard (but only
    # if you are still on the window we sent you to).
    local prev="" cur="" back=0
    if [[ -n "$focus_worker" && "${want_map[$focus_worker]:-0}" != 1 ]]; then
        prev="$focus_worker"
        focus_worker=""
        cur="$(tmux display-message -p -t "$session" '#{window_name}' 2>/dev/null)"
        [[ "$cur" == "$prev" ]] && back=1
    fi
    if [[ -z "$focus_worker" ]]; then
        for w in "${workers[@]}"; do
            if [[ "${want_map[$w]:-0}" == 1 ]]; then
                focus_worker="$w"
                break
            fi
        done
        if [[ -n "$focus_worker" ]]; then
            tmux select-window -t "$session:$focus_worker" 2>/dev/null
        elif (( back )); then
            tmux select-window -t "$session:dashboard" 2>/dev/null
        fi
    fi
}

key=""
while true; do
    (( frame % 6 == 0 )) && refresh_tails
    render
    (( frame += 1 ))

    if (( all_done )) && [[ "${UGU_HEADLESS:-0}" == 1 ]]; then
        tmux kill-session -t "$session" 2>/dev/null
        exit 0
    fi

    key=""
    if [[ -t 0 ]]; then
        read -r -s -k 1 -t 0.08 key 2>/dev/null || key=""
    else
        sleep 0.08
    fi
    case "$key" in
        [1-9])
            (( key <= n_workers )) && tmux select-window -t "$session:${workers[key]}" 2>/dev/null
            ;;
        q|Q|$'\n'|$'\r')
            if (( all_done )); then
                tmux kill-session -t "$session" 2>/dev/null
                exit 0
            fi
            ;;
    esac
done
