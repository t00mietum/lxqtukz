#!/usr/bin/env bash

#  shellcheck disable=2155  ## 'Declare and assign separately to avoid masking return values.' Cumbersome and unnecessary.

##	- Purpose: Starts the release build's session the way a display manager
##	  would, on a headless Wayfire with its own session bus, in the test
##	  container unless --here is given. Then checks that what the session
##	  starts comes from the prefix, not /usr:
##	    - the wallpaper Wayfire's [autostart] hands to swaybg
##	    - D-Bus started services, through the bus's runtime service dir
##	    - xdg-desktop-portal finding our portal and its config
##	- The release comes from cicd/artifacts/release/, extracted to the path it
##	  was built for.
##	- Syntax: cicd/session.bash [--here]
##	History: At bottom of script.

##	Copyright © 2026 t00mietum (CryptogID: ปʬϝღถɔ4რఠΔթะ9ƾǝu)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=utility/include/echo.bash
source "${REPO_ROOT}/cicd/utility/include/echo.bash"

fAbort(){ printf "\nSESSION ABORTED (exit %s) at line %s: %s\n\n" "$1" "$2" "$3" >&2; exit "$1"; }
trap 'fAbort $? $LINENO "$BASH_COMMAND"' ERR

BUILD_IMAGE="lxqtukz-build-debian13"
TEST_IMAGE="lxqtukz-test-debian13"
TARGET="debian13-$(uname -m)"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/version")"
PREFIX="/opt/lxqtukz/versions/${VERSION}"
EXTRACTED="${REPO_ROOT}/work/test/prefix"
PORTAL="org.freedesktop.impl.portal.desktop.lxqt"

declare -i here=0
while (($#)); do case "$1" in
	--here) here=1; shift ;;
	-h|--help) sed -n '/^##\t- Purpose/,/^##\tHistory/p' "${BASH_SOURCE[0]}" | sed 's/^##\t\{0,1\}//'; exit 0 ;;
	*) fDie "unknown argument: $1" ;;
esac; done


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Outside: hand off to the container

if ((! here)); then
	command -v docker >/dev/null || fDie "docker is required; or use --here on a box set up like cicd/linux/Dockerfile.test"
	fSection "Build images"
	docker build -q -t "${BUILD_IMAGE}" -f "${REPO_ROOT}/cicd/linux/Dockerfile" "${REPO_ROOT}/cicd/linux" >/dev/null
	docker build -q -t "${TEST_IMAGE}" -f "${REPO_ROOT}/cicd/linux/Dockerfile.test" "${REPO_ROOT}/cicd/linux" >/dev/null
	tarball="${REPO_ROOT}/cicd/artifacts/release/lxqtukz-${VERSION}-${TARGET}.tar.gz"
	[[ -f "${tarball}" ]] || fDie "no release build at ${tarball}; run cicd/build.bash"
	fSection "Extract ${tarball##*/}"
	if [[ -e "${EXTRACTED}" ]]; then
		[[ -O "${EXTRACTED}" ]] || fDie "${EXTRACTED} is not ours; remove it by hand"
		chmod -R u+w "${EXTRACTED}"; rm -rf "${EXTRACTED}"
	fi
	mkdir -p "${EXTRACTED}"
	tar -C "${EXTRACTED}" -xzf "${tarball}"
	gpu=()
	if [[ -e /dev/dri/renderD128 ]]; then
		gpu=(--device /dev/dri --group-add "$(stat -c %g /dev/dri/renderD128)")
	fi
	passwd="${REPO_ROOT}/work/test/passwd"
	mkdir -p "${passwd%/*}"
	{ echo "root:x:0:0:root:/root:/bin/bash"; echo "tester:x:$(id -u):$(id -g):tester:/tmp:/bin/bash"; } > "${passwd}"
	docker run --rm -i \
		-v "${REPO_ROOT}:/src:ro" -w /src \
		-v "${passwd}:/etc/passwd:ro" \
		-v "${EXTRACTED}/${VERSION}:${PREFIX}:ro" \
		--user "$(id -u):$(id -g)" -e HOME=/tmp \
		"${gpu[@]+"${gpu[@]}"}" \
		"${TEST_IMAGE}" /src/cicd/session.bash --here
	exit 0
fi


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Inside

run="$(mktemp -d "/tmp/test_lxqtukz-session_$(date +%Y%m%d-%H%M%S%2N)_XXXX")"
export HOME="${run}/home" XDG_RUNTIME_DIR="${run}/runtime"
mkdir -p "${HOME}" "${XDG_RUNTIME_DIR}"; chmod 700 "${XDG_RUNTIME_DIR}"
unset XDG_DATA_DIRS XDG_CONFIG_DIRS XDG_CONFIG_HOME XDG_DATA_HOME DISPLAY WAYLAND_DISPLAY

busPid="" sessionPid=""
fStopAll(){
	[[ -z "${sessionPid}" ]] || kill "${sessionPid}" 2>/dev/null || true
	[[ -z "${busPid}" ]] || kill "${busPid}" 2>/dev/null || true
}
trap fStopAll EXIT

declare -i failed=0
fCheck(){ ## label ok|fail [detail]
	if [[ "$2" == ok ]]; then fEcho "ok: $1"; else fEcho "FAIL: $1${3:+ (${3})}"; failed=$((failed + 1)); fi
}

## Waits up to 15 s for a command to succeed.
fWaitFor(){ ## command...
	local _
	for _ in $(seq 75); do "$@" && return 0; sleep 0.2; done
	return 1
}

## The bus a systemd login would have: started before the session, so it never
## saw the prefix.
fSection "Session bus"
busDir="${XDG_RUNTIME_DIR}/dbus-1/services"
mkdir -p "${busDir}"
## One left by an earlier login, and one that isn't ours.
printf '%s\n' "# lxqtukz" "[D-BUS Service]" "Name=org.lxqtukz.Stale" "Exec=/bin/false" > "${busDir}/org.lxqtukz.Stale.service"
printf '%s\n' "[D-BUS Service]" "Name=org.example.Other" "Exec=/bin/false" > "${busDir}/org.example.Other.service"
## A distro's own copy of our portal, as Debian's LXQt has in /usr/share. The
## bus reads it at start, and on its own never takes ours over it.
distroDir="${run}/distro/dbus-1/services"
mkdir -p "${distroDir}"
printf '%s\n' "[D-BUS Service]" "Name=${PORTAL}" "Exec=/bin/false" > "${distroDir}/${PORTAL}.service"
XDG_DATA_DIRS="${run}/distro:/usr/local/share:/usr/share" \
	dbus-daemon --session --nofork --print-address=3 3> "${run}/bus.address" > "${run}/bus.log" 2>&1 &
busPid=$!
fWaitFor test -s "${run}/bus.address" || fDie "dbus-daemon did not start"
export DBUS_SESSION_BUS_ADDRESS="$(head -n1 "${run}/bus.address")"
fEcho "${DBUS_SESSION_BUS_ADDRESS}"

fSection "Start the session"
export WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1
if [[ -r /dev/dri/renderD128 ]]; then
	export WLR_RENDERER=gles2 WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128
else
	export WLR_RENDERER=pixman
fi
"${PREFIX}/bin/startlxqtukz" > "${run}/session.log" 2>&1 &
sessionPid=$!
## The session is up once lxqt-session has handed the bus its environment.
fSessionUp(){ pgrep -x lxqt-session >/dev/null && pgrep -x lxqt-panel >/dev/null; }
if fWaitFor fSessionUp; then fEcho "lxqt-session and lxqt-panel are running"; else
	tail -n 40 "${run}/session.log" >&2; fDie "the session did not come up"
fi
sleep 2

fSection "Wallpaper"
userIni="${HOME}/.config/lxqtukz/wayfire.ini"
splash="$(grep -m1 '^splash[[:space:]]*=' "${userIni}" || true)"
fEcho "${userIni##*/}: ${splash}"
swaybgPid="$(pgrep -x swaybg | head -n1 || true)"
if [[ -z "${swaybgPid}" ]]; then
	fCheck "swaybg runs" fail "$(command -v swaybg || echo 'not installed')"
else
	image="$(tr '\0' '\n' < "/proc/${swaybgPid}/cmdline" | sed -n '/^-i$/{n;p;q}')"
	fEcho "swaybg -i ${image}"
	if [[ "${image}" == "${PREFIX}/"* && -f "${image}" ]]; then fCheck "wallpaper from the prefix" ok; else fCheck "wallpaper from the prefix" fail "${image}"; fi
fi

fSection "D-Bus services"
installed="${busDir}/${PORTAL}.service"
if [[ -f "${installed}" ]] && ! grep -q '^SystemdService=' "${installed}"; then fCheck "portal service in the runtime dir, without SystemdService" ok; else
	fCheck "portal service in the runtime dir, without SystemdService" fail "$(ls "${busDir}")"
fi
if [[ ! -e "${busDir}/org.lxqtukz.Stale.service" && -e "${busDir}/org.example.Other.service" ]]; then fCheck "earlier login's file cleared, other files kept" ok; else
	fCheck "earlier login's file cleared, other files kept" fail "$(ls "${busDir}")"
fi
fCall(){ gdbus call --session -d org.freedesktop.DBus -o /org/freedesktop/DBus -m "org.freedesktop.DBus.$1" "${@:2}"; }
fCall StartServiceByName "${PORTAL}" 0 > "${run}/start.out" 2>&1 || true
ownerPid="$(fCall GetConnectionUnixProcessID "${PORTAL}" 2>/dev/null | tr -dc '0-9' | sed 's/^32//' || true)"
## gdbus prints "(uint32 N,)", and the tr above keeps the 32 of uint32.
exe=""
[[ -z "${ownerPid}" ]] || exe="$(readlink "/proc/${ownerPid}/exe" || true)"
fEcho "${PORTAL}: $(cat "${run}/start.out") -> ${exe:-no owner}"
if [[ "${exe}" == "${PREFIX}/"* ]]; then fCheck "D-Bus starts the portal from the prefix" ok; else fCheck "D-Bus starts the portal from the prefix" fail "${exe:-not started}"; fi

fSection "xdg-desktop-portal"
if [[ ! -x /usr/libexec/xdg-desktop-portal ]]; then
	fCheck "xdg-desktop-portal finds our portal" fail "not installed in the test image"
else
	fCall StartServiceByName org.freedesktop.portal.Desktop 0 >/dev/null 2>&1 || true
	## Only portals with a backend get exported, FileChooser from ours. That
	## happens a moment after the portal takes its name.
	fFileChooser(){
		gdbus introspect --session -d org.freedesktop.portal.Desktop -o /org/freedesktop/portal/desktop 2>/dev/null \
			> "${run}/portal.introspect" || true
		grep -q 'interface org\.freedesktop\.portal\.FileChooser ' "${run}/portal.introspect"
	}
	if fWaitFor fFileChooser; then fCheck "xdg-desktop-portal finds our portal" ok; else
		fCheck "xdg-desktop-portal finds our portal" fail "no FileChooser"
	fi
fi

fStopAll
if ((failed)); then
	## Services the bus starts log to the bus's own output.
	tail -n 40 "${run}/bus.log" >&2
	tail -n 30 "${run}/session.log" >&2
	fDie "${failed} check(s) failed"
fi
fEcho "done"


##	History:
##		- 2026-10-14: Created.
