#!/usr/bin/env zsh
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright (c) 2017-2026 Maulik Mistry
#
# Author: Maulik Mistry
# Please share support: https://www.paypal.com/paypalme/m1st0
#                       https://venmo.com/code?user_id=3319592654995456106&created=1753283702
#
# Flatpak updates. Runs on its own (./ugu_flatpak.zsh) or under the
# orchestrator. User installs need no root. System-wide installs use sudo,
# authenticated in this worker's own terminal. A machine without flatpak is
# skipped, not a failure. UGU_ASSUME_YES=1 (or ugu.zsh -y) answers its prompts.


setopt NO_UNSET PIPE_FAIL
SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/ugu_common.zsh" || exit 1

ugu_flatpak_main() {
    local -i failures=0
    local -a yes=()
    [[ "${UGU_ASSUME_YES:-0}" == 1 ]] && yes=( -y )

    ugu_progress flatpak 5 "Flatpak" "Checking for Flatpak"
    if ! command -v flatpak >/dev/null 2>&1; then
        messenger_std "flatpak not found; skipping."
        ugu_progress flatpak 100 "Skipped" "flatpak is not installed"
        return 0
    fi

    ugu_progress flatpak 15 "User apps" "Updating the user installation"
    flatpak update --user "${yes[@]}" || (( failures += 1 ))

    if [[ -n "$(flatpak list --system --columns=application 2>/dev/null)" ]]; then
        ugu_progress flatpak 55 "System apps" "Updating the system installation"
        if ugu_require_sudo; then
            sudo flatpak update --system "${yes[@]}" || (( failures += 1 ))
        else
            (( failures += 1 ))
        fi
    else
        messenger_std "No system-wide Flatpak installs; skipping."
    fi

    if (( failures > 0 )); then
        messenger_end "$failures Flatpak update step(s) failed."
        return 1
    fi
    ugu_progress flatpak 100 "Complete" "Flatpak apps are up to date"
    messenger_end "Flatpak updates completed."
    return 0
}

ugu_run_worker flatpak ugu_flatpak_main
exit $?
