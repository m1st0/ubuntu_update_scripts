# UGU – Ubuntu Grab Updates (BASH or ZSH)

This project is licensed under the BSD 2-Clause License. See the [LICENSE.txt](LICENSE.txt) file for details.
If you find this project useful and would like to support its development, consider donating via PayPal or Venmo: 
[PayPal](https://www.paypal.com/paypalme/m1st0).
[Venmo](https://venmo.com/code?user_id=3319592654995456106&created=1753280522)

© 2025 Maulik Mistry

This project provides a BASH or ZSH script to update an Ubuntu system with support for various features, including manual updates for Firefox, and system maintenance.

## Why this?

Many Ubuntu users face challenges with automatic updates, especially when using Firefox Snap or Deb installations. This script offers a reliable solution for those who prefer manual installations or need to bypass restrictions imposed by certain distributions.

By sharing this, we demonstrate an understanding of system updates, package management, and scripting in BASH and ZSH — valuable for Ubuntu users and developers alike.

## Features

- Manual Firefox update via Mozilla’s release
- Works well for distros that block Firefox Snap, Deb, or prefer a manual install
- Snap refresh is run first to prevent delays
- APT update/upgrade
- Optional cleanup steps
- Compatible with both BASH and ZSH scripts

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

3. Run the appropriate script:

```
./ugu.sh
./ugu.zsh
```

## Firefox Update Strategy

Unlike Snap or Deb installs, this script checks Mozilla’s release site and updates your manually installed Firefox if needed. There used to be issues with the Snap and Deb install changes. I have opted for a manual Firefox installation, which allows for custom update checks.

Your Firefox must be manually extracted into:

```
$HOME/my_applications/firefox/
```

The script will:

- Detect the current version from the binary
- Compare it to Mozilla's latest .tar.xz release

