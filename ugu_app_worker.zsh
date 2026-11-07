#!/usr/bin/env zsh
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright (c) 2017-2026 Maulik Mistry
#
# Author: Maulik Mistry
# Please share support: https://www.paypal.com/paypalme/m1st0
#                       https://venmo.com/code?user_id=3319592654995456106&created=1753283702
#
# Shared application updater. Sourced by the per-application worker scripts
# after ugu_common.zsh. Call it from inside a function run by ugu_run_worker.
#
# ugu_update_app NAME INSTALL_DIR DOWNLOAD_URL [GITHUB_REPO]


ugu_update_app() {
    local app_name="$1" install_dir="$2" download_url="$3" github_repo="${4:-}"
    local app_bin="$install_dir/$app_name"
    local worker="${UGU_WORKER_ID:-$app_name}"
    local current_version="" latest_version="" final_url=""
    local archive="" stage_dir="" archive_root="" listing="" timestamp="" backup_dir=""
    local -i rc=1

    ugu_require_commands curl jq tar awk grep || return 1

    if [[ ! -x "$app_bin" ]]; then
        messenger_end "Cannot find executable: $app_bin"
        return 1
    fi

    {
        ugu_progress "$worker" 5 "Version check" "Checking $app_name release"
        current_version="$("$app_bin" --version 2>/dev/null | awk '{print $NF}')"
        if [[ -z "$current_version" ]]; then
            messenger_end "Could not determine installed $app_name version."
            return 1
        fi

        if [[ -n "$github_repo" ]]; then
            latest_version="$(curl -fsSL --connect-timeout 10 --max-time 30 \
                "https://api.github.com/repos/$github_repo/releases/latest" |
                jq -r '.tag_name // empty')" || return 1
            latest_version="${latest_version#v}"
            final_url="$download_url"
        else
            final_url="$(curl -fsSL --connect-timeout 10 --max-time 30 \
                --retry 2 -o /dev/null -w '%{url_effective}' "$download_url")" || return 1
            latest_version="$(print -r -- "${final_url##*/}" | grep -oE '[0-9]+([.][0-9]+)+' | head -n 1)"
        fi

        if [[ -z "$latest_version" ]]; then
            messenger_end "Could not determine latest $app_name version."
            return 1
        fi

        # is-at-least NEEDED PRESENT succeeds when PRESENT >= NEEDED, so the
        # latest release is the needed version and the installed one is present.
        autoload -Uz is-at-least
        if is-at-least "$latest_version" "$current_version"; then
            ugu_progress "$worker" 100 "Up to date" "$app_name $current_version is current"
            messenger_end "$app_name is already up to date ($current_version)."
            return 0
        fi

        if [[ "$final_url" == *tar.xz* ]]; then
            archive="${TMPDIR:-/tmp}/${app_name}-${worker}-$$.tar.xz"
        elif [[ "$final_url" == *tar.gz* ]]; then
            archive="${TMPDIR:-/tmp}/${app_name}-${worker}-$$.tar.gz"
        else
            archive="${TMPDIR:-/tmp}/${app_name}-${worker}-$$.${final_url##*.}"
        fi

        ugu_progress "$worker" 20 "Downloading" "$app_name $latest_version"
        if ! ugu_download "$final_url" "$archive" "$app_name $latest_version" 20 60; then
            messenger_end "Download failed for $app_name."
            return 1
        fi

        ugu_progress "$worker" 65 "Validating archive" "Checking archive paths and layout"
        listing="$(tar -tf "$archive")" || {
            messenger_end "Could not read downloaded archive."
            return 1
        }

        archive_root="$(print -r -- "$listing" | awk '
            BEGIN { bad=0 }
            /^\// { bad=1 }
            {
                n=split($0,p,"/")
                for (i=1;i<=n;i++) if (p[i]=="..") bad=1
                if ($0=="." || $0=="") next
                if (root=="" ) root=p[1]
                else if (root!=p[1]) bad=1
            }
            END { if (bad || root=="") exit 1; print root }
        ')" || {
            messenger_end "Archive has an unsafe or unexpected directory layout."
            return 1
        }

        ugu_progress "$worker" 72 "Extracting" "Unpacking to a staging directory"
        stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/${app_name}.stage.XXXXXX")" || return 1
        if ! tar -xf "$archive" -C "$stage_dir"; then
            messenger_end "Extraction failed for $app_name."
            return 1
        fi
        rm -f -- "$archive"
        archive=""

        if [[ ! -d "$stage_dir/$archive_root" || ! -x "$stage_dir/$archive_root/$app_name" ]]; then
            messenger_end "Archive does not contain the expected $app_name executable."
            return 1
        fi

        ugu_progress "$worker" 85 "Installing" "Replacing $app_name atomically"
        timestamp="$(date +%Y%m%d%H%M%S)"
        backup_dir="${install_dir}.backup-${timestamp}"
        if ! mv -- "$install_dir" "$backup_dir"; then
            messenger_end "Could not back up existing $app_name installation."
            return 1
        fi

        if ! mv -- "$stage_dir/$archive_root" "$install_dir"; then
            mv -- "$backup_dir" "$install_dir"
            messenger_end "Installation failed; previous $app_name was restored."
            return 1
        fi

        ugu_progress "$worker" 100 "Complete" "$app_name $current_version to $latest_version"
        messenger_end "$app_name updated: $current_version -> $latest_version"
        rc=0
    } always {
        # Runs on success, error, or interrupt: never leave temp files behind.
        [[ -n "$archive" ]] && rm -f -- "$archive"
        [[ -n "$stage_dir" ]] && rm -rf -- "$stage_dir"
    }
    return $rc
}
