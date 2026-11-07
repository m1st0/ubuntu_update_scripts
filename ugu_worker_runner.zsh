#!/usr/bin/env zsh
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright (c) 2017-2026 Maulik Mistry
#
# Author: Maulik Mistry
# Please share support: https://www.paypal.com/paypalme/m1st0
#                       https://venmo.com/code?user_id=3319592654995456106&created=1753283702
#
# Runs one worker inside its own tmux window (its own pty) and records the
# result. Usage: ugu_worker_runner.zsh WORKER SCRIPT STATE_DIR


setopt NO_UNSET PIPE_FAIL
worker="$1"
script="$2"
state_dir="$3"

source "${0:A:h}/ugu_common.zsh" || exit 1

export UGU_STATE_DIR="$state_dir"
export UGU_WORKER_ID="$worker"

# The orchestrator pipes this window's output to a log, then releases every
# runner at once by creating the "go" file. This keeps the log complete.
integer waited=0
while [[ ! -e "$state_dir/go" ]] && (( waited < 200 )); do
    sleep 0.05
    (( waited += 1 ))
done

export UGU_WORKER_START="$EPOCHSECONDS"
ugu_worker_init "$worker" || exit 1

messenger_std "UGU ${(U)worker} worker: own terminal (pty). Ctrl-b 0 returns to the dashboard."
linefeed
ugu_progress "$worker" 0 "Starting" "Launching $worker worker"

zsh "$script"
rc=$?

ugu_done "$worker" "$rc"
print -r -- "$rc" > "$state_dir/results/$worker.rc.tmp"
mv -f -- "$state_dir/results/$worker.rc.tmp" "$state_dir/results/$worker.rc"

ugu_fmt_time $(( EPOCHSECONDS - UGU_WORKER_START ))
linefeed
if (( rc != 0 )); then
    messenger_end "✗ $worker failed (exit $rc) after $REPLY"
else
    messenger_end "✓ $worker finished in $REPLY"
fi
messenger_std "This window stays open. Ctrl-b 0 returns to the dashboard."
exit "$rc"
