#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 krunner-services-freq contributors
# SPDX-License-Identifier: LGPL-2.0-only
#
# Removes the frequency-aware applications runner and switches the stock one
# back on. Run it as your normal user, not as root: it asks for sudo itself.
#
# The launch statistics stay in place, so reinstalling keeps the history. To
# drop them as well, remove the state directory too (see README).

set -euo pipefail

runner_id="krunner_services_freq"
stock_id="krunner_services"

step() { printf '\n==> %s\n' "$*"; }
ok()   { printf '    %s\n' "$*"; }
die()  { printf '\nerror: %s\n' "$*" >&2; exit 1; }

restart_unit() {
    local unit="$1"
    if systemctl --user restart "$unit" 2>/dev/null; then
        ok "restarted $unit"
    else
        ok "could not restart $unit, it will pick the change up at your next login"
    fi
}

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    die "run this as your normal user, without sudo: the script asks for root only where it needs it"
fi

plugin_root="$(qtpaths6 --plugin-dir 2>/dev/null || true)"
[[ -n "$plugin_root" ]] || die "cannot locate the Qt plugin directory (qtpaths6 is required)"
dest="$plugin_root/kf6/krunner/$runner_id.so"

step "Remove"
if [[ -f "$dest" ]]; then
    printf '    removing a system-wide file, so sudo is used, a password prompt may appear here\n'
    sudo -n true 2>/dev/null || sudo -v || die "sudo failed"
    sudo rm -f "$dest"
    ok "$dest"
else
    ok "nothing installed at $dest"
fi

step "Restore the stock runner"
if command -v kwriteconfig6 >/dev/null 2>&1; then
    kwriteconfig6 --file krunnerrc --group Plugins --key "$stock_id"Enabled true
    kwriteconfig6 --file krunnerrc --group Plugins --key "$runner_id"Enabled --delete
    ok "${stock_id}Enabled=true, ${runner_id}Enabled removed"
else
    ok "warning: kwriteconfig6 not found, edit krunnerrc by hand"
fi

step "Reload"
restart_unit plasma-krunner.service
restart_unit plasma-plasmashell.service

printf '\nDone. Applications are ranked by name again.\n'
