#!/usr/bin/env zsh
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright (c) 2017-2026 Maulik Mistry
#
# Author: Maulik Mistry
# Please share support: https://www.paypal.com/paypalme/m1st0
#                       https://venmo.com/code?user_id=3319592654995456106&created=1753283702
#
# Runs on its own (./ugu_thunderbird.zsh) or under the orchestrator.


setopt NO_UNSET PIPE_FAIL
SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/ugu_common.zsh" || exit 1
source "$SCRIPT_DIR/ugu_app_worker.zsh" || exit 1

ugu_thunderbird_main() {
    ugu_update_app thunderbird "$HOME/my_applications/thunderbird" \
        "https://download.mozilla.org/?product=thunderbird-latest&os=linux64&lang=en-US" \
        ""
}

ugu_run_worker thunderbird ugu_thunderbird_main
exit $?
