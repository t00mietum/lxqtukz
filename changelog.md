# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!--
## vNEXT - DATE

### Notes

### Upstream

### Added

### Changed

### Removed

### Other work
-->

## v0.1.0-alpha1 - unreleased

### Notes

- First release line. Nothing published yet.

### Upstream

- LXQt 2.4.0 (lxqt-panel and pcmanfm-qt 2.4.1), libqtxdg 4.4.0, lxqt-wayland-session 0.4.1, Wayfire 0.11.0.

### Added

- liblxqt: settings directory name taken from `LXQT_CONFIG_NAME`, so all of LXQtukz's settings live in `~/.config/lxqtukz/` and `/etc/xdg/lxqtukz/`.

- `startlxqtukz` session launcher for LXQt on Wayfire.

- `install.bash` / `lxqtukz-update`: install, update, switch to any version, roll back, on Debian 13 and NixOS.

- NixOS flake with an overlay and a `services.lxqtukz` module.

### Other work

- Upstream tracking and patch-queue tooling (`cicd/upstream.bash`).

- Debian 13 container build (`cicd/build.bash`).
