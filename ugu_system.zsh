#!/usr/bin/env zsh
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright (c) 2017-2026 Maulik Mistry
#
# Author: Maulik Mistry
# Please share support: https://www.paypal.com/paypalme/m1st0
#                       https://venmo.com/code?user_id=3319592654995456106&created=1753283702
#
# Snap and APT updates. Runs on its own (./ugu_system.zsh) or under the
# orchestrator. It authenticates sudo for itself in its own terminal.
# Set UGU_ASSUME_YES=1 (or run ugu.zsh -y) to answer apt prompts automatically.


setopt NO_UNSET PIPE_FAIL
SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/ugu_common.zsh" || exit 1

ugu_system_main() {
    local pending upgrade_count suffix=""
    local -a yes=() warnings=()
    [[ "${UGU_ASSUME_YES:-0}" == 1 ]] && yes=( -y )

    ugu_require_commands snap apt-fast apt python3 || return 1

    ugu_progress system 2 "Authenticating" "Checking sudo in this terminal"
    ugu_require_sudo || return 1

    # Snap and APT are independent. A failure in one is a warning and the other
    # still runs. Losing sudo, or a failed APT upgrade, stops the worker.
    ugu_progress system 5 "Snap refresh" "Checking for snap updates"
    pending="$(snap refresh --list 2>&1)" || pending=""
    if [[ "$pending" == *"All snaps up to date"* ]]; then
        messenger_std "All snaps are up to date."
    else
        ugu_progress system 8 "Snap refresh" "Refreshing installed snaps"
        if sudo snap refresh; then
            ugu_progress system 20 "Snap cleanup" "Removing disabled snap revisions"
            if [[ -r "$SCRIPT_DIR/vendor/snap_cleanup/snap_cleanup.py" ]]; then
                python3 "$SCRIPT_DIR/vendor/snap_cleanup/snap_cleanup.py" || warnings+=( "snap cleanup failed" )
            else
                messenger_std "Snap cleanup helper not found; skipping."
            fi
        else
            warnings+=( "snap refresh failed" )
            messenger_std "WARNING: snap refresh failed; continuing with APT."
            ugu_note system "WARNING: snap refresh failed"
        fi
    fi

    ugu_progress system 35 "APT update" "Refreshing package indexes"
    # A failed index update is not fatal: show the error, then upgrade anyway.
    if ! sudo apt-fast update; then
        warnings+=( "apt update failed, upgraded from existing package lists" )
        messenger_std "WARNING: apt update failed; upgrading from existing package lists."
        ugu_note system "WARNING: apt update failed"
    fi
    (( ${#warnings} )) && suffix=" (warning: ${(j:; :)warnings})"

    upgrade_count="$(apt list --upgradable 2>/dev/null | grep -c '/')" || true
    if [[ "$upgrade_count" == <-> ]] && (( upgrade_count > 0 )); then
        ugu_progress system 60 "APT full-upgrade" "$upgrade_count package(s) available"
        sudo apt-fast "${yes[@]}" full-upgrade || return $?

        ugu_progress system 90 "APT clean" "Cleaning downloaded package archives"
        sudo apt clean || return $?
        ugu_progress system 100 "Complete" "Snap and APT done, $upgrade_count package(s) upgraded$suffix"
    else
        ugu_progress system 100 "Complete" "Snap and APT done, no package upgrades$suffix"
    fi
    messenger_end "System updates completed."
    return 0
}

ugu_run_worker system ugu_system_main
exit $?
