#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 krunner-services-freq contributors
# SPDX-License-Identifier: LGPL-2.0-only
#
# Builds and installs the applications runner that ranks results by launch
# frequency, switches the stock applications runner off and restarts the
# processes that load runners. Run it as your normal user, not as root: it asks
# for sudo itself.
#
# Safe to run again at any time. This is also the repair command after a KF6
# update, which may leave a runner built against the previous ABI in place
# (see README).

set -euo pipefail

runner_id="krunner_services_freq"
stock_id="krunner_services"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build_dir="$here/build"
log="$build_dir/install.log"

step() { printf '\n==> %s\n' "$*"; }
ok()   { printf '    %s\n' "$*"; }
die()  { printf '\nerror: %s\n' "$*" >&2; exit 1; }

packages_hint() {
    cat >&2 <<'EOF'

Install the build tools and the KF6 development packages for your distribution:

  Fedora:        sudo dnf install cmake ninja-build gcc-c++ extra-cmake-modules qt6-qtbase-devel \
                     kf6-krunner-devel kf6-kcoreaddons-devel kf6-ki18n-devel kf6-kjobwidgets-devel \
                     kf6-kio-devel kf6-kservice-devel plasma-activities-devel
  Debian/Ubuntu: sudo apt install cmake ninja-build g++ extra-cmake-modules qt6-base-dev \
                     libkf6runner-dev libkf6coreaddons-dev libkf6i18n-dev libkf6jobwidgets-dev \
                     libkf6kio-dev libkf6service-dev libplasmaactivities-dev
  otherwise:     cmake, ninja, a C++ compiler and your distribution's KF6 Runner, KIO,
                 Service, CoreAddons, I18n and JobWidgets development packages
EOF
}

# Ask for root only when sudo would actually prompt: a passwordless setup (or an
# already authorised sudo) goes through without a single question.
root() {
    sudo -n true 2>/dev/null || sudo -v || die "sudo failed"
}

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

# ------------------------------------------------------------------ build deps
step "Build requirements"
missing=""
for tool in cmake ninja c++ qtpaths6 kwriteconfig6; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if [[ -n "$missing" ]]; then
    printf 'missing:%s\n' "$missing" >&2
    packages_hint
    exit 1
fi
ok "cmake, ninja, c++, qtpaths6, kwriteconfig6"

plugin_root="$(qtpaths6 --plugin-dir 2>/dev/null || true)"
[[ -n "$plugin_root" ]] || die "cannot locate the Qt plugin directory (qtpaths6 is required)"
dest="$plugin_root/kf6/krunner/$runner_id.so"

mkdir -p "$build_dir"
# A cache left over from an earlier attempt (another KF6 version, another
# compiler) can make cmake fail on stale values, so every run starts from a
# clean configure. Compiling stays incremental.
rm -f "$build_dir/CMakeCache.txt"
if ! cmake -S "$here" -B "$build_dir" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo >"$log" 2>&1; then
    printf 'cmake could not configure the build; the usual reason is a missing package.\n' >&2
    packages_hint
    printf '\ncmake said:\n' >&2
    tail -n 5 "$log" >&2
    printf '\nFull log: %s\n' "$log" >&2
    exit 1
fi
ok "KF6 development files"

# ----------------------------------------------------------------------- build
step "Build"
if ! cmake --build "$build_dir" >>"$log" 2>&1; then
    printf 'build failed:\n' >&2
    tail -n 20 "$log" >&2
    printf '\nFull log: %s\n' "$log" >&2
    exit 1
fi

so_src="$build_dir/bin/kf6/krunner/$runner_id.so"
[[ -f "$so_src" ]] || die "the build produced no $so_src"
ok "$runner_id.so"

# --------------------------------------------------------------------- install
step "Install"
printf '    installing system-wide, so sudo is used, a password prompt may appear here\n'
root
sudo install -Dm755 "$so_src" "$dest"
# SELinux (enforcing) needs the system library type, otherwise krunner and
# plasmashell cannot open the file.
if command -v restorecon >/dev/null 2>&1; then
    sudo restorecon -F "$dest"
fi
ok "$dest"

# Both applications runners answer the same queries, so the stock one is turned
# off: two identical result lists are worse than a replaced one. The plugin is
# not deleted, so uninstall.sh is a single key flip away.
kwriteconfig6 --file krunnerrc --group Plugins --key "${runner_id}Enabled" true
kwriteconfig6 --file krunnerrc --group Plugins --key "${stock_id}Enabled" false
ok "enabled in krunnerrc: ${runner_id}Enabled=true, ${stock_id}Enabled=false"

# ---------------------------------------------------------------------- reload
step "Reload"
# Runners are mapped at process start; nothing reloads them in place. KRunner
# serves Alt+Space, plasmashell serves the Overview and Kickoff search.
restart_unit plasma-krunner.service
restart_unit plasma-plasmashell.service
sleep 2

# ---------------------------------------------------------------------- verify
step "Verify"
# `krunner --list` is the same plugin scan KRunner does at runtime: it proves
# the runner sits in the directory KRunner looks at and its metadata parses.
if command -v krunner >/dev/null 2>&1 && krunner_list="$(krunner --list 2>/dev/null)" && grep -q "$runner_id" <<<"$krunner_list"; then
    ok "$(grep "$runner_id" <<<"$krunner_list")"
    loaded=0
else
    ok "krunner does not list the runner"
    loaded=1
fi

printf '\ninstalled: %s\n' "$dest"
printf 'statistics: %s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/krunner-services-freq/counts"

if [[ $loaded -eq 0 ]]; then
    printf '\nDone. Type "term" in KRunner: the applications you launch most come first.\n'
else
    cat <<'EOF'

The file is in place, but KRunner does not offer the runner. Its own log line
would say why:

  journalctl --user -u plasma-krunner.service -b --no-pager | tail -n 20
EOF
    exit 1
fi
