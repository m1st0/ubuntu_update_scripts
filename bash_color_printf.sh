#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2017-2026 Maulik Mistry
# SPDX-License-Identifier: Apache 2.0
#
# bash_color_printf.sh - Script to print colored responses or return to normal.\
#
# Author: Maulik Mistry
# Please share support: https://www.paypal.com/paypalme/m1st0
#                       https://venmo.com/code?user_id=3319592654995456106&created=1753283702


# Colors and messaging functions for BASH
red="\033[0;31m"
yellow="\033[0;33m"
end_text="\033[0m\n"

linefeed() {
  printf "\n"
}

messenger_std() {
  printf "${yellow}$1${end_text}";
}

messenger_end() {
  printf "${red}$1${end_text}";
}
