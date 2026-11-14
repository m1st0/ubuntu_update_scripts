#!/usr/bin/env zsh
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright (c) 2017-2026 Maulik Mistry
#
# Author: Maulik Mistry
# Please share support: https://www.paypal.com/paypalme/m1st0
#                       https://venmo.com/code?user_id=3319592654995456106&created=1753283702
#
# UGU orchestrator: runs the update workers in parallel, each in its own tmux
# window (its own pty), with a live dashboard in window 0, then reports.
#
#   ./ugu.zsh                     menu in a terminal, everything when there is none
#   ./ugu.zsh -a                  everything, no menu
#   ./ugu.zsh -o system,tools     only those workers, no menu
#   ./ugu.zsh -m                  always show the menu
#   ./ugu.zsh -y                  answer apt prompts automatically
#
# Requires gum (https://github.com/charmbracelet/gum#installation).
#
# Every worker also runs on its own, for example ./ugu_system.zsh.


setopt NO_UNSET PIPE_FAIL
umask 077

SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/ugu_common.zsh" || exit 1

typeset -a o_yes o_help o_only o_menu o_all
zparseopts -D -E -- y=o_yes -yes=o_yes h=o_help -help=o_help o:=o_only -only:=o_only \
    m=o_menu -menu=o_menu a=o_all -all=o_all || exit 2

if (( ${#o_help} )); then
    print -r -- "Usage: ugu.zsh [-a|--all] [-m|--menu] [-y|--yes] [-o|--only worker[,worker...]]"
    print -r -- "  (no options) menu in a terminal; everything when there is no terminal"
    print -r -- "  -a, --all   run everything now, no menu"
    print -r -- "  -m, --menu  always show the menu, even if you chose to stop asking"
    print -r -- "  -y, --yes   answer apt prompts automatically (UGU_ASSUME_YES=1)"
    print -r -- "  -o, --only  run only the named workers, e.g. --only system,tools"
    print -r -- "Workers: firefox thunderbird zen system tools flatpak firmware"
    exit 0
fi
(( ${#o_yes} )) && export UGU_ASSUME_YES=1

typeset -a workers
workers=( firefox thunderbird zen system tools flatpak firmware )
(( ${#o_only} )) && workers=( ${(s:,:)${o_only[-1]}} )

if (( EUID == 0 )); then
    messenger_end "Run UGU as a normal user, not as root or through sudo."
    exit 1
fi

ugu_require_commands tmux gum apt-fast || {
    messenger_end "Install the missing command(s) above. gum: https://github.com/charmbracelet/gum#installation"
    exit 1
}

# ---------------------------------------------------------------------------
# Menu. It only fills in what the flags would have set (the worker list and
# UGU_ASSUME_YES); everything after it runs exactly as if you had typed that
# command line. Quit, Esc and Ctrl-C all exit cleanly without starting anything.
# ---------------------------------------------------------------------------
typeset menu_dir="${XDG_CONFIG_HOME:-$HOME/.config}/ugu"
typeset menu_marker="$menu_dir/skip-menu"

ugu_menu() {
    local -a all_workers=( firefox thunderbird zen system tools flatpak firmware )
    local -a chosen=()
    local choice="" picked=""

    choice="$(gum choose --header 'UGU: what should run?' \
        "Everything" \
        "Everything (and stop asking)" \
        "System only (snap and apt)" \
        "Tools only (rust, uv, AstroNvim)" \
        "Apps only (firefox, thunderbird, zen)" \
        "Pick workers..." \
        "Quit")" || return 1

    case "$choice" in
        "Everything (and stop asking)")
            mkdir -p -- "$menu_dir" && : > "$menu_marker"
            messenger_std "Saved. UGU will run everything without asking."
            messenger_std "Bring the menu back with: ugu.zsh --menu   (or delete $menu_marker)"
            chosen=( "${all_workers[@]}" )
            ;;
        Everything)  chosen=( "${all_workers[@]}" ) ;;
        System*)     chosen=( system ) ;;
        Tools*)      chosen=( tools ) ;;
        Apps*)       chosen=( firefox thunderbird zen ) ;;
        Pick*)
            # Space ticks a worker and Enter confirms. Enter with nothing ticked
            # returns an empty list, which is asked again, not treated as a
            # cancel. Esc or Ctrl-C cancels.
            local -i rc=0 tries=0
            while (( tries < 5 )); do
                picked="$(gum choose --no-limit \
                    --header 'Space ticks a worker, Enter confirms, Esc cancels' \
                    "${all_workers[@]}")"
                rc=$?
                (( rc == 0 )) || return 1
                chosen=( ${(f)picked} )
                (( ${#chosen} )) && break
                messenger_std "Nothing was ticked. Press Space on each worker you want, then Enter."
                (( tries += 1 ))
            done
            ;;
        *)           return 1 ;;
    esac
    (( ${#chosen} )) || return 1
    workers=( "${chosen[@]}" )

    if (( ${chosen[(Ie)system]} )) && [[ "${UGU_ASSUME_YES:-0}" != 1 ]]; then
        gum confirm --default=false "Answer apt prompts automatically (-y)?"
        case $? in
            0) export UGU_ASSUME_YES=1 ;;
            1) ;;
            *) return 1 ;;
        esac
    fi
    return 0
}

# Show the menu when asked for, or by default in a terminal when nothing was
# chosen and you have not told it to stop asking. No terminal means everything.
typeset -i want_menu=0
if (( ${#o_menu} )); then
    want_menu=1
elif (( ${#o_only} == 0 && ${#o_all} == 0 )) \
    && [[ -t 0 && -t 1 && ! -e "$menu_marker" && "${UGU_ALWAYS_ALL:-0}" != 1 ]]; then
    want_menu=1
fi

if (( want_menu )); then
    if [[ ! -t 0 || ! -t 1 ]]; then
        messenger_end "--menu needs an interactive terminal."
        exit 1
    fi
    ugu_menu || { messenger_std "Nothing started."; exit 0 }
fi

typeset worker script
for worker in "${workers[@]}"; do
    script="$SCRIPT_DIR/ugu_${worker}.zsh"
    if [[ ! -x "$script" ]]; then
        messenger_end "Unknown or non-executable worker: $worker ($script)"
        exit 1
    fi
done

typeset -g UGU_SESSION="ugu-${UID}-$$"
typeset -g UGU_SOCKET="$UGU_SESSION"
typeset -gx UGU_STATE_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/ugu-${UID}-$$"
mkdir -m 700 "$UGU_STATE_DIR" "$UGU_STATE_DIR/results" "$UGU_STATE_DIR/logs" || exit 1
print -r -- "$EPOCHSECONDS" > "$UGU_STATE_DIR/start"

if [[ ! -t 0 || ! -t 1 ]]; then
    # Unattended: no one can answer prompts, so never wait for input.
    # sudo must work without a password; apt prompts are answered with yes.
    export UGU_HEADLESS=1 UGU_NONINTERACTIVE=1
    export UGU_ASSUME_YES="${UGU_ASSUME_YES:-1}"
fi

# A private tmux server: your own tmux config, sessions and key bindings are
# never touched, and the workers inherit this shell's PATH (cargo, uv, ...).
tm() { env -u TMUX tmux -u -L "$UGU_SOCKET" -f /dev/null "$@" }

ugu_abort() {
    tm kill-session -t "$UGU_SESSION" 2>/dev/null
}
trap 'ugu_abort; exit 130' INT TERM HUP

ugu_shell_command() {
    local arg
    local -a quoted=()
    for arg in "$@"; do
        quoted+=( "${(q)arg}" )
    done
    REPLY="${(j: :)quoted}"
}

integer cols lines
cols="$(tput cols 2>/dev/null)" || cols=120
lines="$(tput lines 2>/dev/null)" || lines=40
(( cols >= 40 )) || cols=120
(( lines >= 12 )) || lines=40

# Window 0: dashboard.
ugu_shell_command zsh "$SCRIPT_DIR/ugu_dashboard.zsh" "$UGU_STATE_DIR" "$UGU_SESSION" "${workers[@]}"
if ! tm new-session -d -s "$UGU_SESSION" -n dashboard -x "$cols" -y "$lines" "$REPLY"; then
    messenger_end "Could not create the tmux session."
    exit 1
fi

tm set-option -g status-position top
tm set-option -g status-interval 1
tm set-option -g mouse on
tm set-option -g remain-on-exit on
tm set-option -g automatic-rename off
tm set-option -g status-style 'bg=colour234,fg=colour250'
tm set-option -g status-left-length 20
tm set-option -g status-left '#[bg=colour212,fg=colour16,bold] UGU #[default] '
tm set-option -g status-right '#[fg=colour244]Ctrl-b 0 dashboard  n/p switch  d detach  mouse: click a tab '
tm set-option -gw @ugu_icon ''
tm set-option -gw @ugu_color colour245
tm set-option -g window-status-separator ''
tm set-option -g window-status-format ' #[fg=#{@ugu_color}]#{@ugu_icon}#[fg=colour245]#I:#W '
tm set-option -g window-status-current-format '#[bg=colour212,fg=colour16,bold] #{@ugu_icon}#I:#W #[default]'

for worker in "${workers[@]}"; do
    script="$SCRIPT_DIR/ugu_${worker}.zsh"
    ugu_shell_command zsh "$SCRIPT_DIR/ugu_worker_runner.zsh" "$worker" "$script" "$UGU_STATE_DIR"
    if ! tm new-window -d -t "$UGU_SESSION:" -n "$worker" "$REPLY"; then
        messenger_end "Could not create a tmux window for $worker."
        ugu_abort
        exit 1
    fi
    # Keep a full copy of each worker's terminal output for the final report.
    tm pipe-pane -o -t "$UGU_SESSION:$worker" "cat >> ${(q)UGU_STATE_DIR}/logs/${worker}.log"
done
tm select-window -t "$UGU_SESSION:dashboard"

# Release the runners now that every window exists and is being logged.
: > "$UGU_STATE_DIR/go"

if [[ "${UGU_HEADLESS:-0}" == 1 ]]; then
    messenger_std "No terminal attached; running headless. Session: $UGU_SESSION"
    while tm has-session -t "$UGU_SESSION" 2>/dev/null; do sleep 1; done
else
    typeset answer
    while tm has-session -t "$UGU_SESSION" 2>/dev/null; do
        tm attach-session -t "$UGU_SESSION" || break
        tm has-session -t "$UGU_SESSION" 2>/dev/null || break
        messenger_std "Detached while UGU is still running."
        messenger_std_inline "[r] reattach   [l] leave it running in the background   [k] kill it: "
        read -r -s -k 1 answer
        linefeed
        case "$answer" in
            l|L)
                messenger_std "Reattach later with: tmux -L $UGU_SOCKET attach -t $UGU_SESSION"
                exit 0
                ;;
            k|K) ugu_abort ;;
        esac
    done
fi

# ---------------------------------------------------------------------------
# Report. The orchestrator reads the recorded results, not terminal output.
# ---------------------------------------------------------------------------

typeset -i failures=0
typeset state pct stage msg wstart wupd rc_value icon cc
typeset -a report_lines failed_workers

for worker in "${workers[@]}"; do
    state="missing"; pct=0; stage="No result"; msg="The worker never reported"; wstart=0; wupd=0
    [[ -r "$UGU_STATE_DIR/$worker.state" ]] && IFS='|' read -r state pct stage msg wstart wupd < "$UGU_STATE_DIR/$worker.state"
    rc_value=""
    [[ -r "$UGU_STATE_DIR/results/$worker.rc" ]] && rc_value="$(<"$UGU_STATE_DIR/results/$worker.rc")"

    if [[ "$state" == done && "$rc_value" == 0 ]]; then
        icon="✓"; cc="$COLOR_SUCCESS"
    else
        icon="✗"; cc="$COLOR_ERROR"
        (( failures += 1 ))
        failed_workers+=( "$worker" )
        [[ "$state" == done ]] && state="failed"
    fi
    ugu_fmt_time $(( wupd - wstart ))
    report_lines+=( "$(printf '%s%s%s%s  %-12s %-16s %s  %s' \
        "$BOLD" "$cc" "$icon" "$RESET" "$worker" "$stage" "$REPLY" "$msg")" )
done

ugu_fmt_time $(( EPOCHSECONDS - $(<"$UGU_STATE_DIR/start") ))
typeset total_time="$REPLY"
typeset title="UGU complete in $total_time"
(( failures > 0 )) && title="UGU finished with $failures failure(s) in $total_time"

linefeed
typeset border=42
(( failures > 0 )) && border=196
gum style --border rounded --border-foreground "$border" --padding '1 2' \
    "$(gum style --bold --foreground "$border" "$title")" "" "${report_lines[@]}"

# Failure details come from the per-window logs.
for worker in "${failed_workers[@]}"; do
    linefeed
    messenger_end "$worker: last output"
    if [[ -r "$UGU_STATE_DIR/logs/$worker.log" ]]; then
        tr '\r' '\n' < "$UGU_STATE_DIR/logs/$worker.log" \
            | sed -E 's/\x1b\[[0-9;?]*[ -\/]*[@-~]//g' \
            | sed -E 's/^[[:space:]]*((█|░)+)[[:space:]]+[0-9]+%[[:space:]]+//' \
            | grep -v '^[[:space:]]*$' | uniq | tail -n 12 | sed 's/^/    /'
    fi
done

if (( failures > 0 )); then
    linefeed
    messenger_std "Logs kept in: $UGU_STATE_DIR/logs"
    exit 1
fi
rm -rf -- "$UGU_STATE_DIR"
exit 0
