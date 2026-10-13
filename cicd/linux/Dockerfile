##	Debian 13 (trixie) build box for LXQtukz release builds.
##	A release runs on the distro it was built on or newer, so this pins the
##	floor: a debian13 build needs Debian 13's Qt 6.8 and glibc 2.41.
##	The package list is a first cut, from upstream build docs; refine it from
##	the first full build's failures rather than ahead of them.

FROM debian:trixie

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
	build-essential ca-certificates cmake file git meson ninja-build pkg-config python3 xz-utils \
	qt6-base-dev qt6-base-private-dev qt6-tools-dev qt6-tools-dev-tools qt6-l10n-tools \
	qt6-svg-dev qt6-wayland-dev qt6-wayland-dev-tools \
	libkf6windowsystem-dev libkf6solid-dev libkf6idletime-dev libkf6screen-dev \
	liblayershellqtinterface-dev libpolkit-qt6-1-dev libpolkit-agent-1-dev \
	libglib2.0-dev libmenu-cache-dev libexif-dev libmuparser-dev libudev-dev \
	libx11-dev libxcb1-dev libxcb-util-dev libxcb-damage0-dev libxcb-xkb-dev libxcb-composite0-dev \
	libxcb-res0-dev libxcb-icccm4-dev libxcb-ewmh-dev libxcursor-dev libxkbcommon-dev libxkbcommon-x11-dev \
	libxi-dev libxtst-dev libxdamage-dev libxcomposite-dev libxrender-dev libxss-dev \
	libasound2-dev libpulse-dev libsensors-dev libstatgrab-dev libupower-glib-dev libxkbfile-dev \
	libutf8proc-dev perl \
	wayland-protocols libwayland-dev libwayland-bin libegl-dev libgles-dev libdrm-dev libgbm-dev \
	libinput-dev libevdev-dev libpixman-1-dev libcairo2-dev libpango1.0-dev libjpeg-dev libpng-dev \
	libglm-dev libseat-dev libdisplay-info-dev libliftoff-dev hwdata libvulkan-dev glslang-tools \
	liblcms2-dev libxcb-render-util0-dev libxcb-errors-dev xwayland libgomp1 \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /src
