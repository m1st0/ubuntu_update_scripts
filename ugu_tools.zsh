#!/usr/bin/env zsh
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright (c) 2017-2026 Maulik Mistry
#
# Author: Maulik Mistry
# Please share support: https://www.paypal.com/paypalme/m1st0
#                       https://venmo.com/code?user_id=3319592654995456106&created=1753283702
#
# Rust, uv and AstroNvim updates. Runs on its own (./ugu_tools.zsh) or under
# the orchestrator. A tool that is not installed is skipped, not a failure.


setopt NO_UNSET PIPE_FAIL
SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/ugu_common.zsh" || exit 1

ugu_tools_main() {
    local -i failures=0

    ugu_progress tools 5 "Rust" "Updating Rust toolchains"
    if command -v rustup >/dev/null 2>&1; then
        rustup update || (( failures += 1 ))
    else
        messenger_std "rustup not found; skipping."
    fi

    ugu_progress tools 40 "uv" "Updating uv"
    if command -v uv >/dev/null 2>&1; then
        uv self update || (( failures += 1 ))
    else
        messenger_std "uv not found; skipping."
    fi

    ugu_progress tools 70 "AstroNvim" "Pulling Neovim configuration"
    if [[ -d "$HOME/.config/nvim/.git" ]] && command -v git >/dev/null 2>&1; then
        git -C "$HOME/.config/nvim" pull --ff-only || (( failures += 1 ))
    else
        messenger_std "AstroNvim git checkout not found; skipping."
    fi

    if (( failures > 0 )); then
        messenger_end "$failures development update(s) failed."
        return 1
    fi

    ugu_progress tools 100 "Complete" "Development tools are up to date"
    messenger_end "Development updates completed."
    return 0
}

ugu_run_worker tools ugu_tools_main
exit $?
