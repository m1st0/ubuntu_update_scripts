#!/usr/bin/env zsh
# SPDX-FileCopyrightText: Copyright (c) 2017-2026 Maulik Mistry
# SPDX-License-Identifier: Apache 2.0
#
# zsh_color_printf.sh - Script to print colored responses or return to normal.\
#
# Author: Maulik Mistry
# Please share support: https://www.paypal.com/paypalme/m1st0
#                       https://venmo.com/code?user_id=3319592654995456106&created=1753283702


# Colors and messaging functions for ZSH
red="\033[0;31m"
yellow="\033[0;33m"
end_text="\033[0m\n"

linefeed() {
  printf "\n"
}

messenger_std() {
  printf "%b" "${yellow}$1${end_text}"
}

messenger_end() {
  printf "%b" "${red}$1${end_text}"
}

# https://github.com/<ollama-repo>
# Portions of output formatting inspired by Ollama (MIT License)
alert="$( (/usr/bin/tput bold || :; /usr/bin/tput setaf 1 || :) 2>&-)"
plain="$( (/usr/bin/tput sgr0 || :) 2>&-)"

status() { echo ">>> $*" >&2; }
error() { echo "${alert}ERROR:${plain} $*"; exit 1; }
warning() { echo "${alert}WARNING:${plain} $*"; }

