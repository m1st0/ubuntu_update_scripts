# UGU – Ubuntu Grab Updates (BASH or ZSH)

This project provides a BASH or ZSH script to update an Ubuntu system with support for various features, including manual updates for Firefox, and system maintenance.

© 2026 Maulik Mistry

This project is licensed under the BSD 2-Clause License. See the [LICENSE.txt](LICENSE.txt) file for details.
If you find this project useful and would like to support its development, consider donating: 
- [PayPal](https://www.paypal.com/paypalme/m1st0)
- [Venmo](https://venmo.com/code?user_id=3319592654995456106&created=1753280522)

## Why this?

Many Ubuntu users face challenges with automatic updates, especially when using Firefox Snap or Deb installations. 
This script offers a reliable solution for those who prefer manual installations or need to bypass restrictions imposed by certain distributions.

A demonstration of system updates, package management, and scripting in BASH and ZSH — valuable for Ubuntu users and developers alike.

## Features

- Exampled upgrades via release URLs under "$HOME/my_applications/$app_name"
- Works well for distros that block applications like Firefox in Snap or Deb, or preferring a manual install
- Exampled neovim, fwupdmgr, flatpak, rust toolchain upgrades 
- Snap refresh is run first to prevent delays
- APT update/upgrade
- Optional cleanup steps
- BASH and ZSH scripts

## Requirements

- BASH or ZSH
- Git

## Setup and Usage

1. Clone this repo and make the script executable:

```
git clone https://github.com/m1st0/ugu.git ugu
cd ugu
```

2. Make the desired script executable:

```
chmod +x ugu.zsh
chmod +x ugu.sh
```

3. Run the script of your chosen shell:

```
./ugu.sh
./ugu.zsh
```

## Mozilla (and Zen) Update Strategy

Unlike Snap or Apt installs, this script checks Mozilla’s (Zen's) release site and updates your manually installed Firefox/Thunderbird/Zen if needed. There used to be issues with the Snap and Apt install changes. I have opted for a manual Mozilla product installation, which allows for custom update checks.

Your Firefox/Thunderbird/Zen must previously and respectively installed into:

```
$HOME/my_applications/firefox/
$HOME/my_applications/thunderbird/
$HOME/my_applications/zen/
```

The script will:

- Detect the current version from the binary
- Compare it to Mozilla's latest .tar.xz release

