# krunner-services-freq

A KRunner runner (a Plasma Search plugin) for Plasma 6 that ranks applications
by how often you launch them.

It replaces the stock applications runner. Search works the same way, but the
results you actually use move up: after a few launches, `kon` offers Konsole
before Kontact, and `term` stops hiding your terminal.

- One launch counts once for the application, and separately for the desktop
  action you picked (Konsole's "New Tab" does not outrank Konsole itself).
- The bonus fades: a favourite you have not touched for two weeks slowly sinks,
  so moving from one application to another takes a few launches, not a reset.
- The same runner serves KRunner (`Alt+Space`), the Overview search and Kickoff:
  one result order everywhere.
- No settings, no service, no database. Launch counts live in a plain text file
  that you can read, edit or delete.

## Why this exists

KRunner used to boost results by launch frequency. Upstream removed that
ranking: it made the result order differ between sessions, and "the list is in
the wrong order" reports stopped being reproducible. The stock applications
runner has ranked by name alone ever since.

This repository is that behaviour, rebuilt as a separate runner: a copy of the
upstream applications runner with launch counters added. No system library is
patched, nothing is replaced in `/usr`, and the stock runner stays installed —
it is only switched off in `krunnerrc`, and back on by `uninstall.sh`.

## How the ranking works

Every match gets its upstream relevance multiplied by

```
1 + 0.5 · (1 − e^(−0.3·count)) · 0.5^(age_days / 14)
```

| Constant | Value |
|---|---|
| Bonus ceiling | +50% relevance |
| Ramp-up | ≈ +13% after 1 launch, +30% after 3, +47% after 10 |
| Decay | bonus halves every 14 days |
| Counter | per application and per desktop action |
| Counts cap | 30 launches (the curve is flat long before that) |

A multiplier, not an added constant, because upstream relevance is measured on
different scales per match group: names sit in the hundreds, categories around
0.4–0.6, actions around 0.5–0.65. Multiplying keeps the order inside each group
and only changes the order between groups.

Launching a desktop action bumps the action and the application: using Konsole
"New Tab" is using Konsole. The application's own counter never promotes its
actions.

## Requirements

- Plasma 6 with KF6 6.19 or newer. Developed on Plasma 6.7.5 / KF6 6.31.
- X11 or Wayland, it makes no difference: this is a runner, not an effect.
- The build tools and the KF6 development packages. `install.sh` checks for them
  and prints the exact package names for your distribution if something is
  missing.

## Install

```sh
git clone https://github.com/crabiosa/krunner-services-freq
cd krunner-services-freq
./install.sh
```

The runner is a plugin, so it is installed **system-wide** and the script uses
sudo. If your setup wants a password, you get that prompt once and the script
announces it right before.

The runner shows up as **Applications (freq)** in System Settings → Search →
Plasma Search, next to the stock **Applications** runner it replaces.

`install.sh` also:

- switches the stock applications runner off in `krunnerrc` (it stays installed);
- restarts `plasma-krunner` and `plasmashell`, so the change applies at once.
  The panel blinks while plasmashell restarts — that is the whole side effect.

Then type `term` in KRunner, launch your terminal, and repeat: it climbs with
each launch, and three of them are enough to beat an application you rarely use.

## Reset or forget

```sh
rm ~/.local/state/krunner-services-freq/counts
```

The file is reread when it changes, so this takes effect without a restart. To
forget a single application, delete its line instead of the whole file:

```
# count|last_used|desktop-id|action
12|1792521554|org.kde.konsole.desktop|
3|1792521500|org.kde.konsole.desktop|new-tab
```

## Uninstall

```sh
./uninstall.sh
```

It removes the `.so`, switches the stock runner back on and restarts the same
two processes. Launch statistics stay where they are, so reinstalling keeps the
history; remove the state directory above if you want it gone.

## After a Plasma or KF6 update

A runner built against another KF6 version can be ignored silently, and the
applications simply go back to name order. Rerun the installer:

```sh
./install.sh
```

## Limits

- The ranking is per application, not per query: the runner does not learn that
  `vid` means VLC for you and `ter` means a terminal.
- One fixed half-life (14 days) and one bonus ceiling: no tuning, by design.
- The statistics file is local and user-specific. Nothing reads it but this
  runner, and nothing uploads it anywhere.

Not affiliated with KDE.

## License

LGPL-2.0-only, the license of the plasma-workspace applications runner this is
derived from. `src/bitap.h` and `src/levenshtein.h` are copied unchanged from KF6
KRunner and keep their upstream license
(`LGPL-2.1-only OR LGPL-3.0-only OR LicenseRef-KDE-Accepted-LGPL`). License
texts are in `LICENSES/`.

## No support

Issues and pull requests are not accepted, and there is no support. This is a
personal tool that happens to be useful to others.
