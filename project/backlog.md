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

- [Conventions](#conventions)
- [Milestones](#milestones)
	- [Milestone 1 - First Debian build](#milestone-1---first-debian-build)
	- [Milestone 2 - First NixOS build](#milestone-2---first-nixos-build)
	- [Milestone 3 - All settings in one place](#milestone-3---all-settings-in-one-place)
	- [Milestone 4 - CI/CD and first release](#milestone-4---cicd-and-first-release)
	- [Milestone 5 - tukzedo-linux](#milestone-5---tukzedo-linux)
- [Backlog](#backlog)
	- [Misc to-do](#misc-to-do)
	- [Patches to send upstream](#patches-to-send-upstream)
	- [Done](#done)
- [Future and/or deferred](#future-andor-deferred)
- [Canceled](#canceled)

<!-- /TOC -->

## Conventions

In each section, items are listed approximately from newest to oldest. A patch item names its component, and says if it should go upstream.

| Icon | Status
| :--: | :--
| 🔘   | Not started
| 🛠️   | Started, and/or partially complete
| ✋   | Defer
| ✅   | Complete
| 🚫   | Canceled

## Milestones

### Milestone 1 - First Debian build

- 🔘 Run `cicd/build.bash` all the way through in the Debian 13 container.
	- Note: the Dockerfile package list and `upstream/flags/*` will likely need fixes.

- 🔘 Stop components from installing files outside the prefix. The build script lists them.
	- Note: likely lxqt-qtplugin's platform theme in Qt's plugin dir, xdg-desktop-portal-lxqt's D-Bus service and portal files, and polkit and systemd files.

- 🔘 Make D-Bus started services use the prefix instead of `/usr`. That covers notifications, the portal and the polkit agent.
	- Note: session D-Bus service files may need `XDG_DATA_DIRS` set when the bus starts, or a patch.

- 🔘 Point the wallpaper in Wayfire's `[autostart]` at the prefix. Upstream's `lxqt-wayfire.ini` runs `swaybg -i /usr/share/lxqt/wallpapers/...`.
	- Note: either a stage step or an lxqt-wayland-session patch.

- 🔘 First login on a real Debian 13 machine and in a VM. Check panel, runner, notifications, power, config center, file manager and terminal.

- 🔘 After a version switch and a new login, no session process should still be running from the old version.

### Milestone 2 - First NixOS build

- 🔘 Get `nix flake check` to pass, then build `packages.x86_64-linux.default`. The `nix/` files have never been evaluated.

- 🔘 Build Wayfire with its bundled wlroots on Nix. The `tweaks.wayfire` input list in `nix/overlay.nix` may be missing some.

- 🔘 Try the module in a test VM. The session should show up in the display manager, `/etc/xdg/lxqtukz/` should be filled in, and the timer should exist.

- 🔘 Run `lxqtukz-update --to` on NixOS against a real tag, through re-lock and rebuild.

### Milestone 3 - All settings in one place

- 🔘 List every config path in every component. Search all pinned sources for `QSettings(`, `XdgDirs::configHome`, `"lxqt"` and `.config/`. Mark each as covered by the liblxqt patch or needing its own.

- 🔘 pcmanfm-qt and libfm-qt: move settings from `~/.config/pcmanfm-qt/<profile>/` under `LXQT_CONFIG_NAME`, by patch or by setting the profile.

- 🔘 qterminal: move settings from `~/.config/qterminal.org/` under `LXQT_CONFIG_NAME`.

- 🔘 Wayfire: layer its config so changes to `/etc/xdg/lxqtukz/wayfire.ini` reach existing users.
	- Note: look at wf-config's dynamic-ini backend first.

- 🔘 Pick where LXQt module defaults come from, patched upstream files or our own copies. Patched upstream files for now.

### Milestone 4 - CI/CD and first release

- 🔘 Bring over the nemo-anywhere pipeline. `cicd.bash` stage engine, `config.bash` set up for `upstream.bash` and `build.bash`, pre-push merge gate, version-bump guard on the `version` file, `release.bash`, `changelog-notes.bash`, and backup and publish.
	- Note: the pipeline and pre-push hook should run the content scrub only if it's present.

- 🔘 Branch protection on `main`.

- 🔘 Publish v0.1.0-alpha1 as a prerelease, and install it with `--channel dev` on a clean Debian 13.

- 🔘 Sign `sha256sums.txt` with minisign or sigstore, and have the installer check it.

- 🔘 arm64 Debian build.

### Milestone 5 - tukzedo-linux

- 🔘 Pick where tukzedo's own defaults go. tukzedo could provide `/etc/xdg/lxqtukz/` itself, or this repo could have a profile for it.

- 🔘 tukzedo Debian edition: preinstall with `install.bash -y --to <pinned>`.

- 🔘 tukzedo NixOS edition: module turned on with its settings.

## Backlog

### Misc to-do

- 🔘 Decide on the rest of the LXQt apps: lximage-qt, lxqt-archiver, screengrab, lxqt-openssh-askpass and lxqt-admin.

- 🔘 Updater: show the release's changelog section before asking to switch.

- 🔘 Updater: `--from` on NixOS, pointing the input at a local path.

- 🔘 `cicd/upstream.bash`: `status --fetch` to update mirrors before comparing, and a 1-line summary for the merge gate.

### Patches to send upstream

- 🔘 lxqt-wayland-session: `lxqt-wayfire.ini` hardcodes `/usr/share/lxqt/...`. Send upstream a change that installs it with the configured paths.

- 🔘 liblxqt: send the `LXQT_CONFIG_NAME` patch upstream once it's been in use a while.

### Done

- ✅ Installer and updater for Debian 13.
	- Done: install, switch to any version, rollback, prune and uninstall.
	- Verified: all of those work. Not tried yet with a real release, since there is none.

- ✅ liblxqt patch 0001, settings directory name from `LXQT_CONFIG_NAME`.
	- Verified: applies to 2.4.0, rebases cleanly onto 2.3.0, and compiles against Qt 6.8.

- ✅ Repository, pins for LXQt 2.4 and Wayfire 0.11.0, and patch queue tooling.
	- Verified: apply, refresh and bump, on liblxqt.

## Future and/or deferred

- ✋ Ubuntu LTS and Debian 14 targets.

- ✋ A small `.deb` that runs the installer, for `apt install`.

- ✋ Make wlroots its own component, if it ever needs patches.

## Canceled
