#!/usr/bin/env bash

#  shellcheck disable=2155  ## 'Declare and assign separately to avoid masking return values.' Cumbersome and unnecessary.

##	- Purpose: Checks, builds and tries out the settings app (source/settings/),
##	  in the test container unless --here is given.
##	- Stages, run in the order given. With none named, all but fmt run:
##	    fmt     rewrites the code the way rustfmt wants it
##	    check   shellcheck on this script, rustfmt, clippy with warnings as
##	            errors, and the unit tests
##	    build   release build, to work/build/settings/release/lxqtukz-settings
##	    gui     runs the release build on a headless Wayfire, opens each tab,
##	            and saves a screenshot of each to cicd/artifacts/settings/,
##	            then one tab again under a dark LXQt palette (dark-*.png).
##	            The compositor uses the GPU render node when there is one.
##	    keys    drives the app from the keyboard on that same Wayfire, and
##	            checks what reaches wayfire.ini after each step
##	    dogfood copies the release build to ~/.local/bin/lxqtukz-settings.
##	            Runs on the host, last. Only the latest is kept, and the copy
##	            is skipped while that binary is running.
##	- Syntax: cicd/settings.bash [--here] [fmt] [check] [build] [gui] [keys] [dogfood]
##	History: At bottom of script.

##	Copyright © 2026 t00mietum (CryptogID: ปʬϝღถɔ4რఠΔթะ9ƾǝu)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=utility/include/echo.bash
source "${REPO_ROOT}/cicd/utility/include/echo.bash"

fAbort(){ printf "\nSETTINGS ABORTED (exit %s) at line %s: %s\n\n" "$1" "$2" "$3" >&2; exit "$1"; }
trap 'fAbort $? $LINENO "$BASH_COMMAND"' ERR

BUILD_IMAGE="lxqtukz-build-debian13"
TEST_IMAGE="lxqtukz-test-debian13"
CRATE="${REPO_ROOT}/source/settings"
TARGET_DIR="${REPO_ROOT}/work/build/settings"
SHOTS="${REPO_ROOT}/cicd/artifacts/settings"

declare -i here=0
stages=()
while (($#)); do case "$1" in
	--here) here=1; shift ;;
	fmt|check|build|gui|keys|dogfood) stages+=("$1"); shift ;;
	-h|--help) sed -n '/^##\t- Purpose/,/^##\tHistory/p' "${BASH_SOURCE[0]}" | sed 's/^##\t\{0,1\}//'; exit 0 ;;
	*) fDie "unknown argument: $1" ;;
esac; done
((${#stages[@]})) || stages=(check build gui keys dogfood)

## The first of these that exists gets the dogfood copy. Local, not synced:
## this box is the only one it is tried on.
DOGFOOD_DIRS=("${HOME}/.local/bin")
DOGFOOD_NAME="lxqtukz-settings"

## True if a running process is executing this file. Linux refuses to open a
## running program for writing ("Text file busy"), whoever asks. Reading
## /proc/*/exe would not do: under `sg docker` this script's group differs from
## the program's, and the kernel then hides each process's exe link.
fInUse(){ ## file
	[[ -f "$1" && -w "$1" ]] || return 1
	if (: >> "$1") 2>/dev/null; then return 1; fi
	return 0
}

fStage_dogfood(){
	fSection "Dogfood"
	local built="${TARGET_DIR}/release/${DOGFOOD_NAME}" dir="" d
	[[ -x "${built}" ]] || fDie "no release build at ${built}"
	for d in "${DOGFOOD_DIRS[@]}"; do
		if [[ -d "${d}" && -w "${d}" ]]; then dir="${d}"; break; fi
	done
	if [[ -z "${dir}" ]]; then
		fEcho "skipped: none of these exists: ${DOGFOOD_DIRS[*]}"
		return 0
	fi
	local dest="${dir}/${DOGFOOD_NAME}"
	## A symlink there, as an older stage left, is replaced by the file itself.
	if [[ ! -L "${dest}" ]] && cmp -s "${built}" "${dest}"; then
		fEcho "already current: ${dest}"
	elif fInUse "${dest}"; then
		fEcho "skipped: ${dest} is running; close it and run the dogfood stage again"
	else
		## Through a temporary name and a rename, so the bare name is never a
		## half-copied file.
		local temp="${dir}/.${DOGFOOD_NAME}.$$.tmp"
		cp -f "${built}" "${temp}"
		chmod 0755 "${temp}"
		## The dir's group, not whatever group this run happens to have.
		chgrp "$(stat -c %g "${dir}")" "${temp}" 2>/dev/null || true
		mv -f "${temp}" "${dest}"
		fEcho "installed: ${dest}"
	fi
}


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Outside: hand off to the container

if ((! here)); then
	command -v docker >/dev/null || fDie "docker is required; or use --here on a box set up like cicd/linux/Dockerfile.test"
	fSection "Build images"
	docker build -q -t "${BUILD_IMAGE}" -f "${REPO_ROOT}/cicd/linux/Dockerfile" "${REPO_ROOT}/cicd/linux" >/dev/null
	docker build -q -t "${TEST_IMAGE}" -f "${REPO_ROOT}/cicd/linux/Dockerfile.test" "${REPO_ROOT}/cicd/linux" >/dev/null
	mkdir -p "${REPO_ROOT}/work/cargo" "${TARGET_DIR}"
	## Run as the host user, so nothing in the tree ends up owned by root. The
	## render node's group comes along so the compositor can use the GPU.
	gpu=()
	if [[ -e /dev/dri/renderD128 ]]; then
		gpu=(--device /dev/dri --group-add "$(stat -c %g /dev/dri/renderD128)")
	fi
	## Dogfood happens here on the host, after the rest. It needs a release
	## build, which costs nothing when the last one is still current.
	inside=() dogfood=0
	for stage in "${stages[@]}"; do
		if [[ "${stage}" == dogfood ]]; then dogfood=1; else inside+=("${stage}"); fi
	done
	if ((dogfood)) && [[ " ${inside[*]} " != *" build "* ]]; then inside+=(build); fi
	if ((${#inside[@]})); then
		docker run --rm -i \
			-v "${REPO_ROOT}:/src" -w /src \
			--user "$(id -u):$(id -g)" \
			-e HOME=/tmp -e CARGO_HOME=/src/work/cargo -e KEYS_TRACE="${KEYS_TRACE:-0}" \
			"${gpu[@]+"${gpu[@]}"}" \
			"${TEST_IMAGE}" /src/cicd/settings.bash --here "${inside[@]}"
	fi
	((! dogfood)) || fStage_dogfood
	fEcho "done: ${stages[*]}"
	exit 0
fi


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Inside

export CARGO_TARGET_DIR="${TARGET_DIR}"
jobs=$(( $(nproc) / 2 > 0 ? $(nproc) / 2 : 1 ))
cd "${CRATE}"

fStage_fmt(){
	fSection "rustfmt"
	cargo fmt
}

fStage_check(){
	fSection "shellcheck"
	## From cicd/, where the source= directive's path starts.
	(cd "${REPO_ROOT}/cicd" && shellcheck -x settings.bash)
	fSection "rustfmt"
	cargo fmt --check
	fSection "clippy"
	cargo clippy --all-targets -j "${jobs}" -- -D warnings
	fSection "tests"
	cargo test -j "${jobs}"
}

fStage_build(){
	fSection "Release build"
	cargo build --release -j "${jobs}"
	fEcho "$(stat -c '%s' "${TARGET_DIR}/release/lxqtukz-settings") bytes"
}

## A headless Wayfire as the display. The app edits the same wayfire.ini the
## compositor runs from, as in a real session.
run="" ini="" compositor=""
fCompositor_Start(){
	[[ -z "${compositor}" ]] || return 0
	fSection "Headless Wayfire"
	run="$(mktemp -d "/tmp/test_lxqtukz-settings_$(date +%Y%m%d-%H%M%S%2N)_XXXX")"
	export XDG_RUNTIME_DIR="${run}/runtime" XDG_CONFIG_HOME="${run}/config"
	mkdir -p "${XDG_RUNTIME_DIR}" "${XDG_CONFIG_HOME}" "${run}/session"
	chmod 700 "${XDG_RUNTIME_DIR}"
	## Somewhere other than ~/.config/lxqtukz/, as in a stock LXQt session, so
	## a run only passes if the app follows WAYFIRE_CONFIG_FILE.
	ini="${run}/session/wayfire.ini"
	export WAYFIRE_CONFIG_FILE="${ini}"
	fIni_Reset
	export WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 _WAYFIRE_SOCKET="${run}/wayfire.socket"
	if [[ -r /dev/dri/renderD128 ]]; then
		export WLR_RENDERER=gles2 WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128
	else
		export WLR_RENDERER=pixman
	fi
	fEcho "renderer: ${WLR_RENDERER}${WLR_RENDER_DRM_DEVICE:+ on ${WLR_RENDER_DRM_DEVICE}}"
	wayfire -c "${ini}" > "${run}/wayfire.log" 2>&1 &
	compositor=$!
	trap 'kill "${compositor}" 2>/dev/null || true' EXIT
	local socket="" tries
	for tries in $(seq 50); do
		socket="$(find "${XDG_RUNTIME_DIR}" -maxdepth 1 -type s -name 'wayland-*' -printf '%f\n' | head -n1 || true)"
		[[ -z "${socket}" ]] || break
		sleep 0.1
	done
	if [[ -z "${socket}" ]]; then
		tail -n 30 "${run}/wayfire.log" >&2
		fDie "Wayfire did not start (tries: ${tries})"
	fi
	export WAYLAND_DISPLAY="${socket}" QT_QPA_PLATFORM=wayland WAYFIRE_SOCKET="${_WAYFIRE_SOCKET}"
	unset DISPLAY
}

## The file every keyboard case starts from.
fIni_Reset(){
	cat > "${ini}" <<-'EOF'
		[core]
		plugins = ipc ipc-rules stipc idle cube

		[output:HEADLESS-1]
		mode = 1280x900

		[input]
		kb_repeat_delay = 300
		xkb_layout = us

		[idle]
		dpms_timeout = 600
	EOF
}

## Starts the app on a tab and waits for it to settle. Sets appPid.
appPid=""
fApp_Start(){ ## tab
	local app="${TARGET_DIR}/release/lxqtukz-settings"
	[[ -x "${app}" ]] || fStage_build
	"${app}" --tab "$1" > "${run}/app.log" 2>&1 &
	appPid=$!
	sleep 2
	fTrace start
	kill -0 "${appPid}" 2>/dev/null || { cat "${run}/app.log" >&2; fDie "the app exited on tab $1"; }
}

## Fails on any QML warning the app logged.
fApp_LogClean(){ ## what
	if grep -q -e 'qrc:.*: ' -e 'TypeError' -e 'ReferenceError' "${run}/app.log"; then
		cat "${run}/app.log" >&2
		fDie "QML warnings: $1"
	fi
}

fApp_Stop(){
	kill "${appPid}" 2>/dev/null || true
	wait "${appPid}" 2>/dev/null || true
}

## Waits for the app to close itself, as OK and Cancel should.
fApp_Closed(){ ## what
	local tries
	for tries in $(seq 30); do
		kill -0 "${appPid}" 2>/dev/null || { wait "${appPid}" 2>/dev/null || true; return 0; }
		sleep 0.1
	done
	fApp_Stop
	fDie "$1: the app did not close (tries: ${tries})"
}

fIni_Has(){ ## line what
	grep -qx "$1" "${ini}" && return 0
	sed 's/^/  | /' "${ini}" >&2
	mkdir -p "${SHOTS}"
	grim "${SHOTS}/failed.png" 2>/dev/null || true
	{ echo "  app log:"; sed 's/^/  | /' "${run}/app.log"; echo "  wayfire log, last lines:"; tail -n 15 "${run}/wayfire.log" | cut -c1-200 | sed 's/^/  | /'; } >&2
	fDie "$2: wanted '$1' (screen: cicd/artifacts/settings/failed.png)"
}

## With KEYS_TRACE=1, a screenshot after every step, to see where a case went
## wrong.
declare -i traceStep=0
fTrace(){
	[[ "${KEYS_TRACE:-0}" == 1 ]] || return 0
	traceStep=$((traceStep + 1))
	mkdir -p "${SHOTS}/trace"
	## Nothing to capture while a test has the screen off.
	grim "${SHOTS}/trace/$(printf '%03d' "${traceStep}")-$1.png" 2>/dev/null || true
}

## Keys go in through Wayfire's stipc test plugin, which keeps one keyboard on
## the seat. Tools that bring a new virtual keyboard per run raced the keymap:
## a key could be read with the last run's keymap, so a Tab arrived as Escape.
fKeys(){
	local step name
	for step in "$@"; do
		python3 -I "${REPO_ROOT}/cicd/utility/wayfire-keys.py" "${step}"
		name="${step,,}"
		fTrace "${name//[^a-z0-9+]/}"
	done
}

## The app window's x, y and width on screen.
winX=0 winY=0 winW=0
fWindow(){
	read -r winX winY winW _ < <(python3 -I "${REPO_ROOT}/cicd/utility/wayfire-keys.py" --geometry)
}

## Clicks a row's "Test now" icon: two columns in from the window's right
## edge, at the row's height on its tab.
fTestNow(){ ## row-y
	fWindow
	fKeys "click:$((winX + winW - 73)),$((winY + $1))"
}

## The color of one screen pixel, as "r g b".
fPixel(){ ## x y
	grim -t ppm -g "$1,$2 1x1" - | tail -c 3 | od -An -tu1 | xargs
}

## Whether the screen can be captured, which it cannot while it is off.
fScreenOn(){
	grim -t ppm -g "0,0 1x1" - >/dev/null 2>&1
}

fStage_gui(){
	fCompositor_Start
	mkdir -p "${SHOTS}"
	local tab name
	while IFS= read -r tab; do
		name="${tab,,}"; name="${name//[ \/]/-}"
		fApp_Start "${tab}"
		grim "${SHOTS}/${name}.png"
		fApp_Stop
		fApp_LogClean "tab ${tab}"
		fEcho "${tab} -> cicd/artifacts/settings/${name}.png"
	done < <(sed -n 's/^tabs: \[\(.*\)\]$/\1/p' "${CRATE}/src/settings_ui.shcl" | grep -o '"[^"]*"' | tr -d '"')

	## The text takes the theme's colors only if the app passes the palette on
	## to the desktop style. Without that, this shows dark text on dark.
	mkdir -p "${XDG_CONFIG_HOME}/lxqt"
	cat > "${XDG_CONFIG_HOME}/lxqt/lxqt.conf" <<-'EOF'
		[Palette]
		window_color=#212121
		window_text_color=#f9f9f9
		base_color=#2e2e2d
		text_color=#ececec
		highlight_color=#0054a7
		highlighted_text_color=#ffffff
	EOF
	QT_QPA_PLATFORMTHEME=lxqt fApp_Start "Keyboard"
	grim "${SHOTS}/dark-keyboard.png"
	fApp_Stop
	rm -r "${XDG_CONFIG_HOME}/lxqt"
	fApp_LogClean "dark palette"
	fEcho "Keyboard, dark palette -> cicd/artifacts/settings/dark-keyboard.png"
}

## Drives the app from the keyboard, the way a person would, and checks the
## file Wayfire reads after each step.
fStage_keys(){
	fCompositor_Start
	fSection "Keyboard"

	fIni_Reset
	fApp_Start "Keyboard"
	fKeys Tab Up
	fIni_Has "kb_repeat_delay = 309" "Up on a slider steps a hundredth of the range, live"
	fKeys Escape
	fApp_Closed "Escape"
	fIni_Has "kb_repeat_delay = 300" "Escape puts the value back"
	fEcho "slider step, live write, Escape cancels"

	fIni_Reset
	fApp_Start "Keyboard"
	fKeys Tab Tab text:500 Return
	fApp_Closed "Enter"
	fIni_Has "kb_repeat_delay = 500" "a number typed over the selection, then Enter as OK"
	fEcho "walking onto a field selects it, Enter is OK"

	fIni_Reset
	fApp_Start "Keyboard"
	fKeys Tab Tab Tab Tab Tab text:abc Return
	kill -0 "${appPid}" 2>/dev/null || fDie "Enter in the key repeat test area closed the app"
	fKeys Escape
	fApp_Closed "Escape in the key repeat test area"
	fEcho "Enter in the key repeat test area is a key, not OK"

	fIni_Reset
	fApp_Start "Keyboard"
	fKeys Tab Tab Tab Tab Tab Tab text:de Return
	fApp_Closed "Enter in a text field"
	fIni_Has "xkb_layout = de" "Enter in a text field commits it and is OK"
	fEcho "Enter in a text field is OK"

	fIni_Reset
	fApp_Start "Screensaver and power"
	fKeys ctrl+Tab Tab Down
	fIni_Has "kb_repeat_delay = 291" "Ctrl+Tab goes to the next tab"
	fKeys ctrl+shift+Tab Tab space
	fIni_Has "dpms_timeout = -1" "Ctrl+Shift+Tab goes back, and Space toggles"
	fKeys Escape
	fApp_Closed "Escape after tab changes"
	fIni_Has "kb_repeat_delay = 300" "Escape puts back changes on every tab"
	fIni_Has "dpms_timeout = 600" "Escape puts back changes on every tab"
	fEcho "Ctrl+Tab and Ctrl+Shift+Tab change tabs, Space toggles"

	fIni_Reset
	fApp_Start "Mouse and touchpad/Touchpad"
	fKeys Tab Tab Tab Tab Right
	fIni_Has "touchpad_accel_profile = none" "Right steps a dropdown without opening it"
	fKeys Escape
	fApp_Closed "Escape on the touchpad tab"
	if grep -q touchpad_accel_profile "${ini}"; then fDie "Escape left touchpad_accel_profile behind"; fi
	fEcho "Right steps a dropdown, and Cancel drops an option that was not there"
	fApp_LogClean "keyboard cases"

	fSection "Test now"
	fIni_Reset
	fApp_Start "Screensaver and power"
	fWindow
	local calm; calm="$(fPixel $((winX + 10)) $((winY + 40)))"
	fTestNow 165
	fIni_Has "screensaver_timeout = 1" "the screensaver test cuts its timeout to a second"
	sleep 3
	fTrace screensaver
	[[ "$(fPixel $((winX + 10)) $((winY + 40)))" != "${calm}" ]] || fDie "the screensaver test did not start the screensaver"
	fKeys shift
	sleep 1.5
	if grep -q screensaver_timeout "${ini}"; then fDie "the screensaver test left its timeout behind"; fi
	fEcho "the screensaver test starts it, and a key ends it and puts the timeout back"

	fTestNow 165
	fKeys Escape
	fApp_Closed "Escape during the screensaver test"
	if grep -q screensaver_timeout "${ini}"; then fDie "closing during the screensaver test left its timeout behind"; fi
	fApp_Start "Screensaver and power"
	fEcho "closing during the screensaver test puts the timeout back"

	fTestNow 95
	sleep 2.5
	if fScreenOn; then fDie "the screen-off test left the screen on"; fi
	fKeys shift
	sleep 1
	fScreenOn || fDie "a key did not turn the screen back on after the screen-off test"
	fApp_Stop
	fApp_LogClean "Test now"
	fEcho "the screen-off test turns it off, and a key turns it back on"
}

for stage in "${stages[@]}"; do "fStage_${stage}"; done
fEcho "done: ${stages[*]}"


##	History:
##		- 2026-10-14: Created.
##		- 2026-10-14: Dogfood stage, and every stage by default.
##		- 2026-10-14: Dogfood to ~/.local/bin, and the session's Wayfire file in tests.
##		- 2026-10-14: A screenshot under a dark LXQt palette.
##		- 2026-10-14: Test now cases, and the key repeat test area.
