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
##	            and saves a screenshot of each to cicd/artifacts/settings/.
##	            The compositor uses the GPU render node when there is one.
##	    keys    drives the app from the keyboard on that same Wayfire, and
##	            checks what reaches wayfire.ini after each step
##	    dogfood copies the release build, as plain lxqtukz-settings, into the
##	            first dogfood dir that exists, and keeps a symlink of the same
##	            name in ~/.local/bin so it is on the PATH. Runs on the host,
##	            last. Only the latest is kept, and the copy is skipped while
##	            that binary is running.
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

## The first of these that exists gets the dogfood copy.
DOGFOOD_DIRS=("${HOME}/synced/0-0/common/exec/app/linux")
DOGFOOD_NAME="lxqtukz-settings"
## Where the bare name goes on the PATH, as a symlink to the dogfood copy.
DOGFOOD_LINK_DIR="${HOME}/.local/bin"

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
	if cmp -s "${built}" "${dest}"; then
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

	## A symlink, never a file of its own, so there is one copy to update.
	local link="${DOGFOOD_LINK_DIR}/${DOGFOOD_NAME}"
	if [[ ! -d "${DOGFOOD_LINK_DIR}" ]]; then
		fEcho "no link: ${DOGFOOD_LINK_DIR} does not exist"
	elif [[ -e "${link}" && ! -L "${link}" ]]; then
		fEcho "no link: ${link} is already there as a plain file; left alone"
	elif [[ "$(readlink "${link}" || true)" != "${dest}" ]]; then
		ln -sfn "${dest}" "${link}"
		chgrp -h "$(stat -c %g "${DOGFOOD_LINK_DIR}")" "${link}" 2>/dev/null || true
		fEcho "linked: ${link} -> ${dest}"
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
	mkdir -p "${XDG_RUNTIME_DIR}" "${XDG_CONFIG_HOME}/lxqtukz"
	chmod 700 "${XDG_RUNTIME_DIR}"
	ini="${XDG_CONFIG_HOME}/lxqtukz/wayfire.ini"
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
		plugins = ipc stipc idle cube

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
	grim "${SHOTS}/trace/$(printf '%03d' "${traceStep}")-$1.png"
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
	fKeys Tab Tab Tab Tab Tab text:de Return
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
}

for stage in "${stages[@]}"; do "fStage_${stage}"; done
fEcho "done: ${stages[*]}"


##	History:
##		- 2026-10-14: Created.
##		- 2026-10-14: Dogfood stage, and every stage by default.
