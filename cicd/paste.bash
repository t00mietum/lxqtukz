#!/usr/bin/env bash

#  shellcheck disable=2155  ## 'Declare and assign separately to avoid masking return values.' Cumbersome and unnecessary.

##	- Purpose: Checks copy and paste between apps on a headless Wayfire, in the
##	  test container unless --here is given. Backlog item 2026101417551800.
##	- Wayfire and QTerminal come from the release build in
##	  cicd/artifacts/release/, extracted to the path it was built for. With
##	  --system they are Debian's instead, as a stock LXQt session has them.
##	- Stages. With none named, menu runs:
##	    menu      QTerminal's context menu "Paste Clipboard", with text another
##	              app copied. Runs twice: with the [workarounds] section the
##	              release's wayfire.ini has, which has to paste, and with the
##	              workaround off, which has to fail. Otherwise the check
##	              can't tell the bug from a pass. Ctrl+Shift+V is the control.
##	    xwayland  an X11 client reads and sets the clipboard while a Wayland
##	              window has focus, as SilkTerm does. wlroots refuses both
##	              unless an Xwayland window has focus, so this fails today.
##	              The same with an X window focused is the control.
##	- Syntax: cicd/paste.bash [--here] [--system] [menu] [xwayland]
##	History: At bottom of script.

##	Copyright © 2026 t00mietum (CryptogID: ปʬϝღถɔ4რఠΔթะ9ƾǝu)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=utility/include/echo.bash
source "${REPO_ROOT}/cicd/utility/include/echo.bash"

fAbort(){ printf "\nPASTE ABORTED (exit %s) at line %s: %s\n\n" "$1" "$2" "$3" >&2; exit "$1"; }
trap 'fAbort $? $LINENO "$BASH_COMMAND"' ERR

BUILD_IMAGE="lxqtukz-build-debian13"
TEST_IMAGE="lxqtukz-test-debian13"
TARGET="debian13-$(uname -m)"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/version")"
PREFIX="/opt/lxqtukz/versions/${VERSION}"
EXTRACTED="${REPO_ROOT}/work/test/prefix"
KEYS="${REPO_ROOT}/cicd/utility/wayfire-keys.py"

declare -i here=0 system=0
stages=()
while (($#)); do case "$1" in
	--here) here=1; shift ;;
	--system) system=1; shift ;;
	menu|xwayland) stages+=("$1"); shift ;;
	-h|--help) sed -n '/^##\t- Purpose/,/^##\tHistory/p' "${BASH_SOURCE[0]}" | sed 's/^##\t\{0,1\}//'; exit 0 ;;
	*) fDie "unknown argument: $1" ;;
esac; done
((${#stages[@]})) || stages=(menu)


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Outside: hand off to the container

if ((! here)); then
	command -v docker >/dev/null || fDie "docker is required; or use --here on a box set up like cicd/linux/Dockerfile.test"
	fSection "Build images"
	docker build -q -t "${BUILD_IMAGE}" -f "${REPO_ROOT}/cicd/linux/Dockerfile" "${REPO_ROOT}/cicd/linux" >/dev/null
	docker build -q -t "${TEST_IMAGE}" -f "${REPO_ROOT}/cicd/linux/Dockerfile.test" "${REPO_ROOT}/cicd/linux" >/dev/null
	mounts=()
	if ((! system)); then
		tarball="${REPO_ROOT}/cicd/artifacts/release/lxqtukz-${VERSION}-${TARGET}.tar.gz"
		[[ -f "${tarball}" ]] || fDie "no release build at ${tarball}; run cicd/build.bash, or use --system"
		fSection "Extract ${tarball##*/}"
		## Extracted fresh every run, so a rebuilt release is what gets tested.
		if [[ -e "${EXTRACTED}" ]]; then
			[[ -O "${EXTRACTED}" ]] || fDie "${EXTRACTED} is not ours; remove it by hand"
			chmod -R u+w "${EXTRACTED}"; rm -rf "${EXTRACTED}"
		fi
		mkdir -p "${EXTRACTED}"
		tar -C "${EXTRACTED}" -xzf "${tarball}"
		## At the path it was built for, since rpaths and plugin paths are baked in.
		mounts=(-v "${EXTRACTED}/${VERSION}:${PREFIX}:ro")
	fi
	gpu=()
	if [[ -e /dev/dri/renderD128 ]]; then
		gpu=(--device /dev/dri --group-add "$(stat -c %g /dev/dri/renderD128)")
	fi
	## Xwayland turns away a client whose user has no passwd entry.
	passwd="${REPO_ROOT}/work/test/passwd"
	mkdir -p "${passwd%/*}"
	{ echo "root:x:0:0:root:/root:/bin/bash"; echo "tester:x:$(id -u):$(id -g):tester:/tmp:/bin/bash"; } > "${passwd}"
	flags=()
	((! system)) || flags+=(--system)
	docker run --rm -i \
		-v "${REPO_ROOT}:/src:ro" -w /src \
		-v "${passwd}:/etc/passwd:ro" \
		"${mounts[@]+"${mounts[@]}"}" \
		--user "$(id -u):$(id -g)" -e HOME=/tmp \
		"${gpu[@]+"${gpu[@]}"}" \
		"${TEST_IMAGE}" /src/cicd/paste.bash --here "${flags[@]+"${flags[@]}"}" "${stages[@]}"
	exit 0
fi


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Inside

if ((system)); then
	## Debian has no lxqtukz wayfire.ini, so the patched upstream file stands in.
	releaseIni="${REPO_ROOT}/work/src/lxqt-wayland-session/configurations/lxqt-wayfire.ini"
	[[ -f "${releaseIni}" ]] || fDie "missing ${releaseIni}; run 'cicd/upstream.bash apply lxqt-wayland-session'"
else
	export PATH="${PREFIX}/bin:${PATH}"
	releaseIni="${PREFIX}/etc/xdg/lxqtukz/wayfire.ini"
	[[ -f "${releaseIni}" ]] || fDie "missing ${releaseIni}"
fi
fEcho "wayfire: $(command -v wayfire) ($(wayfire --version 2>&1 | head -n1))"
fEcho "qterminal: $(command -v qterminal)"

run="$(mktemp -d "/tmp/test_lxqtukz-paste_$(date +%Y%m%d-%H%M%S%2N)_XXXX")"
compositor="" app=""
fStopAll(){
	[[ -z "${app}" ]] || kill "${app}" 2>/dev/null || true
	[[ -z "${compositor}" ]] || kill "${compositor}" 2>/dev/null || true
	app="" compositor=""
	## wl-copy and xclip stay behind to serve what they copied.
	pkill -x wl-copy 2>/dev/null || true
	pkill -x xclip 2>/dev/null || true
}
trap fStopAll EXIT

## Starts Wayfire on an ini made from the lines given.
fCompositor_Start(){ ## ini-line...
	fStopAll
	local arm="${run}/arm$((++armCount))"
	mkdir -p "${arm}/runtime" "${arm}/home"
	chmod 700 "${arm}/runtime"
	export XDG_RUNTIME_DIR="${arm}/runtime" HOME="${arm}/home"
	printf '%s\n' "$@" > "${arm}/wayfire.ini"
	export WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 _WAYFIRE_SOCKET="${arm}/wayfire.socket"
	if [[ -r /dev/dri/renderD128 ]]; then
		export WLR_RENDERER=gles2 WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128
	else
		export WLR_RENDERER=pixman
	fi
	wayfire -c "${arm}/wayfire.ini" > "${arm}/wayfire.log" 2>&1 &
	compositor=$!
	local socket="" tries
	for tries in $(seq 50); do
		socket="$(find "${XDG_RUNTIME_DIR}" -maxdepth 1 -type s -name 'wayland-*' -printf '%f\n' | head -n1 || true)"
		[[ -z "${socket}" ]] || break
		sleep 0.1
	done
	if [[ -z "${socket}" ]]; then
		tail -n 30 "${arm}/wayfire.log" >&2
		fDie "Wayfire did not start (tries: ${tries})"
	fi
	export WAYLAND_DISPLAY="${socket}" QT_QPA_PLATFORM=wayland WAYFIRE_SOCKET="${_WAYFIRE_SOCKET}"
	unset DISPLAY
	armDir="${arm}"
}
declare -i armCount=0
armDir=""

fKeys(){ python3 -I "${KEYS}" "$@" >/dev/null; }

## QTerminal running cat, so what it pastes ends up in a file. Sets appCenter.
appCenter=""
fTerminal_Start(){
	: > "${armDir}/pasted"
	qterminal -e "sh -c 'cat >> ${armDir}/pasted'" > "${armDir}/qterminal.log" 2>&1 &
	app=$!
	sleep 3
	kill -0 "${app}" 2>/dev/null || { cat "${armDir}/qterminal.log" >&2; fDie "QTerminal exited"; }
	local winX winY winW winH
	read -r winX winY winW winH < <(python3 -I "${KEYS}" --geometry)
	appCenter="$((winX + winW / 2)),$((winY + winH / 2))"
	fKeys "click:${appCenter}"
}

## True if the line was the last thing pasted.
fPasted(){ ## text
	sleep 0.5
	[[ "$(tail -n 1 "${armDir}/pasted")" == "$1" ]]
}

## The [workarounds] section of the release wayfire.ini, as lines.
fReleaseWorkarounds(){
	awk '/^\[/ { on = ($0 == "[workarounds]"); next } on && !/^[[:space:]]*(#|$)/' "${releaseIni}"
}

## Pastes another app's text through the context menu. Returns 1 if nothing came.
fMenuArm(){ ## label ini-line...
	local label="$1"; shift
	fCompositor_Start "[core]" "plugins = ipc ipc-rules stipc" "xwayland = false" "" "$@"
	fTerminal_Start
	wl-copy "keys-${label}" 2>/dev/null
	fKeys ctrl+shift+v Return
	fPasted "keys-${label}" || fDie "${label}: Ctrl+Shift+V pasted nothing, so the menu result means nothing"
	wl-copy "menu-${label}" 2>/dev/null
	fKeys "rclick:${appCenter}"
	sleep 0.5
	## "Paste Clip&board"
	fKeys b
	fKeys Return
	fPasted "menu-${label}"
}

fStage_menu(){
	fSection "Context menu paste"
	local release
	release="$(fReleaseWorkarounds)"
	fEcho "release [workarounds]: ${release:-none}"
	local -a releaseLines=()
	[[ -z "${release}" ]] || mapfile -t releaseLines <<< "${release}"
	local offOk=0 releaseOk=0
	if fMenuArm off "[workarounds]" "focus_main_surface_instead_of_popup = false"; then offOk=1; fi
	fEcho "workaround off: $( ((offOk)) && echo pasted || echo 'pasted nothing')"
	if fMenuArm release "[workarounds]" "${releaseLines[@]+"${releaseLines[@]}"}"; then releaseOk=1; fi
	fEcho "release settings: $( ((releaseOk)) && echo pasted || echo 'pasted nothing')"
	fStopAll
	((! offOk)) || fDie "the menu pasted with the workaround off too; this Wayfire doesn't show the bug, so the check proves nothing"
	((releaseOk)) || fDie "QTerminal's context menu pastes nothing from another app with the release settings"
}

## An X11 client next to a focused window. Fails on the first refusal.
fXArm(){ ## label
	local label="$1" got
	wl-copy "wl-${label}" 2>/dev/null
	sleep 0.5
	got="$(timeout 3 xclip -o -selection clipboard 2>/dev/null || true)"
	[[ "${got}" == "wl-${label}" ]] || { fEcho "${label}: X11 client could not read what a Wayland app copied"; return 1; }
	printf 'x-%s' "${label}" | xclip -i -selection clipboard
	sleep 0.5
	got="$(timeout 3 wl-paste -n 2>/dev/null || true)"
	[[ "${got}" == "x-${label}" ]] || { fEcho "${label}: what an X11 client copied never reached Wayland apps"; return 1; }
	fEcho "${label}: both ways"
}

fStage_xwayland(){
	fSection "X11 clipboard next to Wayland windows"
	command -v xclip >/dev/null || fDie "xclip is missing from the test image"
	fCompositor_Start "[core]" "plugins = ipc ipc-rules stipc" "xwayland = true"
	local x tries
	for tries in $(seq 50); do
		x="$(find /tmp/.X11-unix -maxdepth 1 -name 'X*' -printf '%f\n' 2>/dev/null | head -n1 || true)"
		[[ -z "${x}" ]] || break
		sleep 0.1
	done
	[[ -n "${x}" ]] || fDie "Xwayland did not start (tries: ${tries})"
	export DISPLAY=":${x#X}"
	xeyes -geometry 200x200+0+0 > /dev/null 2>&1 &
	local eyes=$!
	sleep 1.5
	fKeys click:100,100
	fXArm "x-window-focused" || { kill "${eyes}"; fDie "the control failed with an X window focused, so the setup is broken"; }
	local qt=0
	fTerminal_Start
	fXArm "wayland-window-focused" || qt=1
	kill "${eyes}" 2>/dev/null || true
	fStopAll
	((! qt)) || fDie "X11 clients lose the clipboard while a Wayland window has focus"
}

for stage in "${stages[@]}"; do "fStage_${stage}"; done
fEcho "done: ${stages[*]}"


##	History:
##		- 2026-10-14: Created.
