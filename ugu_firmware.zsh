#!/usr/bin/env zsh
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright (c) 2017-2026 Maulik Mistry
#
# Author: Maulik Mistry
# Please share support: https://www.paypal.com/paypalme/m1st0
#                       https://venmo.com/code?user_id=3319592654995456106&created=1753283702
#
# Firmware updates through fwupd. Runs on its own (./ugu_firmware.zsh) or under
# the orchestrator. A machine without fwupdmgr is skipped, not a failure.
#
# Firmware is only INSTALLED when someone is at the terminal. Unattended runs
# (cron, headless) refresh and report what is available, and never apply it.
# The yes-to-everything option is deliberately not passed to fwupdmgr: it
# would also answer yes to its "reboot now?" question. Answer its prompts in
# this worker's window.


setopt NO_UNSET PIPE_FAIL
SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/ugu_common.zsh" || exit 1

ugu_firmware_main() {
    local -i rc=0
    local -i attended=0
    [[ -t 0 && "${UGU_NONINTERACTIVE:-0}" != 1 ]] && attended=1

    ugu_progress firmware 5 "Firmware" "Checking for fwupdmgr"
    if ! command -v fwupdmgr >/dev/null 2>&1; then
        messenger_std "fwupdmgr not found; skipping."
        ugu_progress firmware 100 "Skipped" "fwupdmgr is not installed"
        return 0
    fi

    # fwupdmgr exits 2 for "nothing to do", which is not an error.
    ugu_progress firmware 15 "Metadata" "Refreshing firmware metadata"
    fwupdmgr refresh --force
    rc=$?
    if (( rc != 0 && rc != 2 )); then
        messenger_std "WARNING: metadata refresh failed (exit $rc); using cached metadata."
        ugu_note firmware "WARNING: metadata refresh failed (exit $rc)"
    fi

    ugu_progress firmware 40 "Check" "Looking for firmware updates"
    fwupdmgr get-updates
    rc=$?
    if (( rc == 2 )); then
        ugu_progress firmware 100 "Complete" "No firmware updates available"
        messenger_end "Firmware is up to date."
        return 0
    elif (( rc != 0 )); then
        messenger_end "fwupdmgr get-updates failed (exit $rc)."
        return $rc
    fi

    if (( ! attended )); then
        messenger_std "Firmware updates are available. Run ugu_firmware.zsh at a terminal to install them."
        ugu_progress firmware 100 "Updates available" "Not installed (unattended); run ugu_firmware.zsh"
        return 0
    fi

    ugu_progress firmware 60 "Installing" "Applying firmware updates (answer prompts here)"
    ugu_require_sudo || return 1
    sudo fwupdmgr update
    rc=$?
    if (( rc != 0 && rc != 2 )); then
        messenger_end "fwupdmgr update failed (exit $rc)."
        return $rc
    fi
    ugu_progress firmware 100 "Complete" "Firmware update finished (a reboot may be needed)"
    messenger_end "Firmware updates completed."
    return 0
}

ugu_run_worker firmware ugu_firmware_main
exit $?
