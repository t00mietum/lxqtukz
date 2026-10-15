<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Requirements

This is a product backlog just for pre-v1.0.0 release. After that, bugs, features, and enhancements will be managed in Github Issues.

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [Issues](#issues)
- [Template](#template)

<!-- /TOC -->

## Issues

Sorted per the notes in [Template](#template). A milestone is a Task, and its items point to it with Parent ID.

- Milestone 3 - All settings in one place
	- ID: 2026101221490202
	- Type: Task
	- Status: Started
	- Opened: 20261012-214902
	- Opened by: t00mietum

- Start work on a unified settings application, ala KDE. This will be our own, we'll eventually remove all other individual OS & desktop settings applications.
	- ID: 2026101412285000
	- Type: Feature
	- Status: Started
	- Opened: 20261014-122850
	- Opened by: t00mietum
	- Parent ID: 2026101221490202
	- Requirements:
		- Our desktop app (for icons and wallpaper management), 'tukzdesk' will have its own settings app, which we'll remove, and use its exposed API from this new settings app.
	- Baseline design: `design_docs/20260930-145721_settings-dialog.md`, adapted from silkterm. Tabs will be on the left.
	- Progress log:
		- 20261014: started as `lxqtukz-settings` in `source/settings/`. Rust, with a Qt Quick interface through cxx-qt, drawn in the desktop's Qt style. Its tabs and rows come from a shcl file built into it.
		- 20261014: `cicd/settings.bash` checks it, and runs it from the keyboard on a Wayfire in the test container. The release build includes it.

- Settings, implement in order of priority:
	- ID: 2026101412285001
	- Type: Feature
	- Status: Started
	- Opened: 20261014-122850
	- Opened by: t00mietum
	- Parent ID: 2026101221490202
	- Requirements:
		- Need a screensaver manager and screen power management app. Something simple and intuitive, like XFCE4's, but integrated into the settings app.
		- Keyboard settings (delay, speed, shortcuts). Like XFCE4's, but integrated into the settings app.
		- Mouse settings. Like XFCE4's, but integrated into the settings app.
	- Progress log:
		- 20261014: a first cut of all 3, through Wayfire's own settings. Screen off and Wayfire's cube screensaver with their timeouts, key repeat, layouts and Num Lock, and the mouse and touchpad. Still to do: a lock screen, power actions and keyboard shortcuts.
		- 20261014: labels were unreadable under a dark theme. Fixed.
		- 20261014: a "Test now" icon on screen off and the screensaver, and a test area for key repeat.
		- 20261014: the tallest tab's last row was cut off when the window opened. Fixed.

- Paste randomly stops working in terminals. QTerminal and SilkTerm. (Critical.)
	- ID: 2026101417551800
	- Type: Bug
	- Status: Waiting for answers
	- Needs local test suite run?: Yes. A full `cicd/build.bash`, then `cicd/paste.bash`. The menu stage has to pass on the release's Wayfire 0.11.
	- Priority|Severity: Critical
	- Opened: 20261014-175518
	- Opened by: t00mietum
	- Test environment: Debian 13, the stock LXQt session on Wayfire 0.9.0 (wlroots 0.18), Qt 6.8.
	- Reproduced: Yes, 20261014, both causes below, on Debian's Wayfire 0.9 headless in the test container. Same packages as this box.
	- Actual cause:
		- QTerminal: since Wayfire 0.9 a context menu takes keyboard focus, and Qt's menu Paste then pastes nothing that another app copied. Ctrl+Shift+V works. Wayfire issue 2600.
		- SilkTerm: its window is Wayland, but it copies and pastes through the X11 clipboard. wlroots only lets X11 apps use the clipboard while an X11 window has focus. So a copy in SilkTerm never reaches other apps, and SilkTerm pastes nothing another app copied. This box has no X11 windows open at all.
	- Progress log:
		- 20261014: ruled out on this box: no clipboard manager or other clipboard watcher runs. KDE Connect runs but has no paired device, so its clipboard plugin isn't loaded. The session log has nothing about the clipboard.
		- 20261014: to confirm on this box with no changes: copy in FeatherPad, then right-click Paste in QTerminal pastes nothing, while Ctrl+Shift+V works. Copy in SilkTerm, then `wl-paste` in QTerminal prints the older text. Nothing in the live config fixes the first on Wayfire 0.9. The option starts at 0.10.
		- 20261014: question: the SilkTerm half can be fixed in SilkTerm, by using the Wayland clipboard when its window is on Wayland. That's the clean fix, but it's SilkTerm's. Or LXQtukz could lift wlroots' rule, with a wlroots patch or a clipboard bridge in the session. Either lets any X11 app read the clipboard at any time, as on X11. Which way?
	- Actual fix [Bug]: QTerminal half: the Wayfire config each release comes with turns on `focus_main_surface_instead_of_popup`, as a patch to upstream's file. SilkTerm half: open.
	- Branch: pastefix
	- Commit: c230370
	- Test case: `cicd/paste.bash` menu stage for the QTerminal half. It fails on Debian's Wayfire 0.9 (`--system`), and with the option off. Its xwayland stage is the SilkTerm half, and fails today.
	- Swept: the Wayfire option covers context-menu paste in every Qt app, QTerminal included. Of the apps running on this box, only SilkTerm has an X11 clipboard connection.

- Stop components from installing files outside the prefix. The build script lists them.
	- ID: 2026101221490206
	- Type: Bug
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490200
	- Note: likely lxqt-qtplugin's platform theme in Qt's plugin dir, xdg-desktop-portal-lxqt's D-Bus service and portal files, and polkit and systemd files.

- Make D-Bus started services use the prefix instead of `/usr`. That covers notifications, the portal and the polkit agent.
	- ID: 2026101221490207
	- Type: Bug
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490200
	- Note: session D-Bus service files may need `XDG_DATA_DIRS` set when the bus starts, or a patch.

- Point the wallpaper in Wayfire's `[autostart]` at the prefix. Upstream's `lxqt-wayfire.ini` runs `swaybg -i /usr/share/lxqt/wallpapers/...`.
	- ID: 2026101221490208
	- Type: Bug
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490200
	- Note: either a stage step or an lxqt-wayland-session patch.

- `cicd/build.bash <component>` can't stage. The container's prefix starts empty on every run, so a partial build has nothing to finish.
	- ID: 2026101415260903
	- Type: Bug
	- Status: Queued
	- Opened: 20261014-152609
	- Opened by: t00mietum

- Milestone 1 - First Debian build
	- ID: 2026101221490200
	- Type: Task
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum

- Milestone 2 - First NixOS build
	- ID: 2026101221490201
	- Type: Task
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum

- Milestone 4 - CI/CD and first release
	- ID: 2026101221490203
	- Type: Task
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum

- Run `cicd/build.bash` all the way through in the Debian 13 container.
	- ID: 2026101221490205
	- Type: Task
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490200
	- Note: the Dockerfile package list and `upstream/flags/*` will likely need fixes.

- First login on a real Debian 13 machine and in a VM. Check panel, runner, notifications, power, config center, file manager and terminal.
	- ID: 2026101221490209
	- Type: Task
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490200

- After a version switch and a new login, no session process should still be running from the old version.
	- ID: 2026101221490210
	- Type: Task
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490200

- Get `nix flake check` to pass, then build `packages.x86_64-linux.default`. The `nix/` files have never been evaluated.
	- ID: 2026101221490211
	- Type: Task
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490201

- Build Wayfire with its bundled wlroots on Nix. The `tweaks.wayfire` input list in `nix/overlay.nix` may be missing some.
	- ID: 2026101221490212
	- Type: Task
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490201

- Try the module in a test VM. The session should show up in the display manager, `/etc/xdg/lxqtukz/` should be filled in, and the timer should exist.
	- ID: 2026101221490213
	- Type: Task
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490201

- Run `lxqtukz-update --to` on NixOS against a real tag, through re-lock and rebuild.
	- ID: 2026101221490214
	- Type: Task
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490201

- List every config path in every component. Search all pinned sources for `QSettings(`, `XdgDirs::configHome`, `"lxqt"` and `.config/`. Mark each as covered by the liblxqt patch or needing its own.
	- ID: 2026101221490215
	- Type: Task
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490202

- pcmanfm-qt and libfm-qt: move settings from `~/.config/pcmanfm-qt/<profile>/` under `LXQT_CONFIG_NAME`, by patch or by setting the profile.
	- ID: 2026101221490216
	- Type: Enhancement
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490202

- qterminal: move settings from `~/.config/qterminal.org/` under `LXQT_CONFIG_NAME`.
	- ID: 2026101221490217
	- Type: Enhancement
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490202

- Wayfire: layer its config so changes to `/etc/xdg/lxqtukz/wayfire.ini` reach existing users.
	- ID: 2026101221490218
	- Type: Feature
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490202
	- Note: look at wf-config's dynamic-ini backend first.

- Pick where LXQt module defaults come from, patched upstream files or our own copies. Patched upstream files for now.
	- ID: 2026101221490219
	- Type: Task
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490202

- CI/CD dogfood: copy each build to its final install location on this box, not to a synced app folder, since this is the only test machine. The settings app already goes to `~/.local/bin`.
	- ID: 2026101418583700
	- Type: Task
	- Status: Queued
	- Opened: 20261014-185837
	- Opened by: t00mietum
	- Parent ID: 2026101221490203

- Bring over the nemo-anywhere pipeline. `cicd.bash` stage engine, `config.bash` set up for `upstream.bash` and `build.bash`, pre-push merge gate, version-bump guard on the `version` file, `release.bash`, `changelog-notes.bash`, and backup and publish.
	- ID: 2026101221490220
	- Type: Task
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490203
	- Note: the pipeline and pre-push hook should run the content scrub only if it's present.

- Publish v0.1.0-alpha1 as a prerelease, and install it with `--channel dev` on a clean Debian 13.
	- ID: 2026101221490221
	- Type: Task
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490203

- Sign `sha256sums.txt` with minisign or sigstore, and have the installer check it.
	- ID: 2026101221490222
	- Type: Feature
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490203

- arm64 Debian build.
	- ID: 2026101221490223
	- Type: Feature
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490203

- Settings app: a search bar, and the planned Appearance, Interface and Hardware tabs.
	- ID: 2026101418182800
	- Type: Feature
	- Status: Queued
	- Opened: 20261014-181828
	- Opened by: t00mietum
	- Note: the full list is in the design doc, `design_docs/20260930-145721_settings-dialog.md`, under Specification and Roadmap.

- Settings app: build it in the NixOS flake. Only the Debian build has it so far.
	- ID: 2026101415260900
	- Type: Task
	- Status: Queued
	- Opened: 20261014-152609
	- Opened by: t00mietum

- Settings app: the rest of its design doc. Reopening on the same tab, keeping the window size for the session, a file another program has open, and a focus ring on sliders.
	- ID: 2026101415260901
	- Type: Feature
	- Status: Queued
	- Opened: 20261014-152609
	- Opened by: t00mietum

- Settings app: try it in a real LXQtukz session, under a few Kvantum themes.
	- ID: 2026101415260902
	- Type: Task
	- Status: Queued
	- Opened: 20261014-152609
	- Opened by: t00mietum

- Create one shcl theme file per personality, and generate all of that personality's theming from it.
	- ID: 2026101412243400
	- Type: Feature
	- Status: Queued
	- Opened: 20261014-122434
	- Opened by: t00mietum
	- Note: tukzedo's own apps, such as silkterm, captain-nemo, the desktop layer and maybe a panel, aren't Qt. Kvantum alone can no longer style a personality.
	- Generated from it: the Kvantum style for other Qt apps, a GTK theme, the style for tukzedo's own apps, silkterm's colors and fonts, and Wayfire's window decorations.
	- Note: try the Rust toolkit for captain-nemo and any panel against 2 very different personalities, such as Windows XP and macOS, before writing much of either.
	- Note: the personalities item itself is in the tukzedo-linux backlog.

- Decide on the rest of the LXQt apps: lximage-qt, lxqt-archiver, screengrab, lxqt-openssh-askpass and lxqt-admin.
	- ID: 2026101221490227
	- Type: Task
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum

- Updater: show the release's changelog section before asking to switch.
	- ID: 2026101221490228
	- Type: Feature
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum

- Updater: `--from` on NixOS, pointing the input at a local path.
	- ID: 2026101221490229
	- Type: Feature
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum

- `cicd/upstream.bash`: `status --fetch` to update mirrors before comparing, and a 1-line summary for the merge gate.
	- ID: 2026101221490230
	- Type: Enhancement
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum

- lxqt-wayland-session: `lxqt-wayfire.ini` hardcodes `/usr/share/lxqt/...`. Send upstream a change that installs it with the configured paths.
	- ID: 2026101221490231
	- Type: Task
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum

- Branch protection.
	- ID: 2026101222253900
	- Type: Task
	- Status: Done
	- Opened: 20261012-222539
	- Opened by: t00mietum
	- Done: rulesets on `main` and `dev` that block force-push and deletion and require a PR, with admin bypass. A ruleset on `v*` tags blocks deletion.
	- Done: secret scanning with push protection, Dependabot alerts and security updates, and private vulnerability reporting.
	- Closed: 20261012-222539

- Installer and updater for Debian 13.
	- ID: 2026101221490233
	- Type: Feature
	- Status: Done
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Done: install, switch to any version, rollback, prune and uninstall.
	- Verified: all of those work. Not tried yet with a real release, since there is none.
	- Closed: 20261012-214902

- liblxqt patch 0001, settings directory name from `LXQT_CONFIG_NAME`.
	- ID: 2026101221490234
	- Type: Feature
	- Status: Done
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Verified: applies to 2.4.0, rebases cleanly onto 2.3.0, and compiles against Qt 6.8.
	- Closed: 20261012-214902

- Repository, pins for LXQt 2.4 and Wayfire 0.11.0, and patch queue tooling.
	- ID: 2026101221490235
	- Type: Task
	- Status: Done
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Verified: apply, refresh and bump, on liblxqt.
	- Closed: 20261012-214902

- Ubuntu LTS and Debian 14 targets.
	- ID: 2026101221490236
	- Type: Feature
	- Status: Deferred
	- Opened: 20261012-214902
	- Opened by: t00mietum

- A small `.deb` that runs the installer, for `apt install`.
	- ID: 2026101221490237
	- Type: Feature
	- Status: Deferred
	- Opened: 20261012-214902
	- Opened by: t00mietum

- Make wlroots its own component, if it ever needs patches.
	- ID: 2026101221490238
	- Type: Feature
	- Status: Deferred
	- Opened: 20261012-214902
	- Opened by: t00mietum

**Stop here for a next release**

- Milestone 5 - tukzedo-linux
	- ID: 2026101221490204
	- Type: Task
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum

- Pick where tukzedo's own defaults go. tukzedo could provide `/etc/xdg/lxqtukz/` itself, or this repo could have a profile for it.
	- ID: 2026101221490224
	- Type: Task
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490204

- tukzedo Debian edition: preinstall with `install.bash -y --to <pinned>`.
	- ID: 2026101221490225
	- Type: Feature
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490204

- tukzedo NixOS edition: module turned on with its settings.
	- ID: 2026101221490226
	- Type: Feature
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum
	- Parent ID: 2026101221490204

- liblxqt: send the `LXQT_CONFIG_NAME` patch upstream once it's been in use a while.
	- ID: 2026101221490232
	- Type: Task
	- Status: Queued
	- Opened: 20261012-214902
	- Opened by: t00mietum

## Template

- Notes:

	- Only use rows that you actually need or expect will be filled in. Always fill in the title, ID, Type, Status, Opened and Created by.

	- The ID is the local time to the hundredth of a second. Opened is when it was written down, which may differ. (Use a keyboard macro and possibly something like project 'zuid' to generate.)

	- Status values meaning: Testing means the fix is in and checks are running or still to run. Waiting on signoff means automated testing passed. Moot means something else changed that made it irrelevant. Canceled means it still applies but was decided against. Waiting for testing means the fix is in and waits on a long CI run or an outside test host. Can't reproduce means a real attempt to reproduce it failed.
		- An item with nothing left for a person to judge skips Waiting on signoff and goes straight to Done. `Clean up the backlog` in the directives says when.

	- As issues are worked, and statuses change, place them in correct sorting order within the list:
		- First by status: Waiting for answers, Waiting on signoff, Testing, Waiting for testing, Can't reproduce, Stalled, Started, Queued, Done, Deferred, Canceled, Moot
		- Then by severity|priority: Critical, High, Avg, Low
		- Then by type: Bugs, [not bugs together]

	- Rows marked [Bug] are for bugs only, and rows marked [Feature] for features and enhancements. Priority and Severity share one row and one scale. Priority is for a Feature or Enhancement, and Severity for a Bug. Children are not nested. They sit at the top level and point back with Parent ID.

Template:

- Title
	- ID: YYYYmmDDHHMMSSNN
	- Type: [Bug|Feature|Enhancement|Task]
	- Status: [Queued|Waiting for answers|Waiting on signoff|Waiting for testing|Started|Testing|Stalled|Can't reproduce|Moot|Canceled|Deferred|Done]
	- Needs local test suite run?:
	- Needs external testing:
	- Priority [Feature|Enhancement] | Severity [Bug]: [Critical|High|Avg|Low]
	- Opened:
	- Opened by:
	- Assigned to:
	- Parent ID:
	- Prereq IDs:
	- Related IDs:
	- Target OS:
	- Test environment:
	- Version and build:
	- Requirements  [Feature]:
		- Hierarchical bulleted list.
	- Steps to reproduce [Bug]:
		- …
	- Incorrect behavior [Bug]:
	- Expected behavior [Bug]:
	- Reproduced [Bug]: [No, or when, where and how]
	- Possible cause [Bug]:
	- Actual cause [Bug]:
		- …
	- Estimated effort: [High|Avg|Low]
	- Actual effort: [High|Avg|Low]
	- Progress log:
		- …
	- Decisions:
		- …
	- Actual fix [Bug]:
	- Branch:
	- Commit:
	- Test case: [Reason not applicable, or CI test case #]
	- Acceptance signoff:
	- Superseded by ID:
	- Closed:
