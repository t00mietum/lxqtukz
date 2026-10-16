#!/usr/bin/env bash

#  shellcheck disable=2155  ## 'Declare and assign separately to avoid masking return values.' Cumbersome and unnecessary.

##	- Purpose: Runs install.bash as root in a throwaway Debian 13 container
##	  and checks what it puts into the system:
##	    - the updater's units with AUTO_UPDATE=no: both linked, the timer off,
##	      and still there to turn on later
##	    - the backlight helper's polkit action: pkexec picks it for the helper
##	      the session runs, a distro LXQt's own action still works, and an
##	      older version's session keeps its own after an update
##	    - prune and --uninstall: no link is left pointing at a removed version
##	- The release comes from cicd/artifacts/release/, or --from. An older
##	  version laid out as builds were before the action got its own name,
##	  and 2 newer ones, are made up in the container, with only the files
##	  the installer links.
##	- systemd doesn't run in the container. A systemctl wrapper makes unit
##	  links offline with --root=/, which is the same code the manager runs
##	  for enable and disable.
##	- Syntax: cicd/installer.bash [--from TARBALL]
##	History: At bottom of script.

##	Copyright © 2026 t00mietum (CryptogID: ปʬϝღถɔ4რఠΔթะ9ƾǝu)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=utility/include/echo.bash
source "${REPO_ROOT}/cicd/utility/include/echo.bash"

fAbort(){ printf "\nINSTALLER TEST ABORTED (exit %s) at line %s: %s\n\n" "$1" "$2" "$3" >&2; exit "$1"; }
trap 'fAbort $? $LINENO "$BASH_COMMAND"' ERR

IMAGE="lxqtukz-test-installer"
TARGET="debian13-$(uname -m)"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/version")"
ROOT="/opt/lxqtukz"
POLKIT_DIR="/usr/share/polkit-1/actions"
DISTRO_ACTION="/usr/share/polkit-1/actions/org.lxqt.backlight.pkexec.policy"
WANTS="/etc/systemd/system/timers.target.wants/lxqtukz-update.timer"

tarball="${REPO_ROOT}/cicd/artifacts/release/lxqtukz-${VERSION}-${TARGET}.tar.gz"
inside=""
while (($#)); do case "$1" in
	--from) tarball="${2:?}"; shift 2 ;;
	--inside) inside="${2:?}"; shift 2 ;;
	-h|--help) sed -n '/^##\t- Purpose/,/^##\tHistory/p' "${BASH_SOURCE[0]}" | sed 's/^##\t\{0,1\}//'; exit 0 ;;
	*) fDie "unknown argument: $1" ;;
esac; done


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Outside: hand off to the container

if [[ -z "${inside}" ]]; then
	command -v docker >/dev/null || fDie "docker is required"
	[[ -f "${tarball}" ]] || fDie "no release build at ${tarball}; run cicd/build.bash"
	tarball="$(cd "$(dirname "${tarball}")" && pwd)/$(basename "${tarball}")"
	fSection "Build image ${IMAGE}"
	docker build -q -t "${IMAGE}" -f "${REPO_ROOT}/cicd/linux/Dockerfile.installer" "${REPO_ROOT}/cicd/linux" >/dev/null
	## No deps file beside the archive, so the installer skips apt.
	exec docker run --rm -i \
		-v "${REPO_ROOT}:/src:ro" \
		-v "${tarball}:/release/${tarball##*/}:ro" \
		"${IMAGE}" /src/cicd/installer.bash --inside "/release/${tarball##*/}"
fi


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Inside

## Root, writing to /usr, /etc and /opt: never on a real system.
[[ -f /.dockerenv ]] || fDie "--inside changes the system it runs on; it only runs in the test container"

run="$(mktemp -d "/tmp/test_lxqtukz-installer_$(date +%Y%m%d-%H%M%S%2N)_XXXX")"
mkdir -p "${run}/release"
cp "${inside}" "${run}/release/"
release="${run}/release/${inside##*/}"
listing="$(tar -tzf "${release}")"
first="${listing%%/*}"
old="0.0.1" next="99.0.0" last="99.0.1"

declare -i failed=0
fCheck(){ ## label ok|fail [detail]
	if [[ "$2" == ok ]]; then fEcho "ok: $1"; else fEcho "FAIL: $1${3:+ (${3})}"; failed=$((failed + 1)); fi
}
fIf(){ ## label command...
	local label="$1"; shift
	if "$@"; then fCheck "${label}" ok; else fCheck "${label}" fail; fi
}

## Waits up to 15 s for a command to succeed.
fWaitFor(){ ## command...
	local _
	for _ in $(seq 75); do "$@" && return 0; sleep 0.2; done
	return 1
}

fLinksTo(){ [[ -L "$1" && "$(readlink "$1")" == "$2" ]]; }

fInstall(){ ## archive
	if bash /src/install.bash --from "$1" -y > "${run}/install.log" 2>&1; then fCheck "install.bash --from ${1##*/}" ok; else
		sed 's/^/  /' "${run}/install.log"; fCheck "install.bash --from ${1##*/}" fail
	fi
}

## A version with only what the installer links, and an action of its own,
## or with 'distro', the distro's file name and action id.
fFakeRelease(){ ## version [distro]
	local dir="${run}/fake/$1" id="org.lxqtukz.backlight-$1"
	[[ "${2:-}" != distro ]] || id="org.lxqt.backlight.pkexec"
	mkdir -p "${dir}/bin" "${dir}/lib/systemd/system" "${dir}/etc/xdg/lxqtukz" "${dir}/share/wayland-sessions" "${dir}/share/polkit-1/actions"
	cp /src/install.bash "${dir}/bin/lxqtukz-update"
	cp /usr/bin/lxqt-backlight_backend "${dir}/bin/"
	cp /src/source/lib/systemd/system/* "${dir}/lib/systemd/system/"
	cp /src/source/etc/xdg/lxqtukz/update.conf "${dir}/etc/xdg/lxqtukz/"
	: > "${dir}/share/wayland-sessions/lxqtukz.desktop"
	cat > "${dir}/share/polkit-1/actions/${id}.policy" <<-EOF
		<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN" "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
		<policyconfig>
		  <action id="${id}">
		    <message>Test</message>
		    <defaults><allow_any>no</allow_any><allow_inactive>no</allow_inactive><allow_active>yes</allow_active></defaults>
		    <annotate key="org.freedesktop.policykit.exec.path">${ROOT}/versions/$1/bin/lxqt-backlight_backend</annotate>
		  </action>
		</policyconfig>
	EOF
	tar -C "${run}/fake" -czf "${run}/fake/lxqtukz-$1-${TARGET}.tar.gz" "$1"
}

## The action pkexec asks polkit about, as the session runs the helper: by
## name, with its version's bin first on PATH. The rule below logs it.
fPkexecAction(){ ## bin-dir-or-path
	local before="$(wc -l < "${run}/polkitd.log")" command="lxqt-backlight_backend" path="$1/bin"
	if [[ -f "$1" ]]; then command="$1"; path="/usr/bin"; fi
	runuser -u tester -- env PATH="${path}:/usr/bin:/bin" pkexec --disable-internal-agent "${command}" --stdin < /dev/null > /dev/null 2>&1 || true
	fWaitFor fNewAction "${before}" || true
	tail -n +"$((before + 1))" "${run}/polkitd.log" | sed -n 's/.*ACTION //p' | tail -n1
}
fNewAction(){ grep -q 'ACTION ' <<< "$(tail -n +"$(($1 + 1))" "${run}/polkitd.log")"; }
fKnown(){ pkaction --action-id "$1" > /dev/null 2>&1; }

fSection "System"
mkdir -p /run/systemd/system /usr/local/sbin
cat > /usr/local/sbin/systemctl <<-'EOF'
	#!/usr/bin/env bash
	## No manager here: unit links are made offline, and nothing is started.
	args=()
	for arg in "$@"; do case "${arg}" in --now) ;; daemon-reload) exit 0 ;; *) args+=("${arg}") ;; esac; done
	exec /usr/bin/systemctl --root=/ "${args[@]}"
EOF
chmod 755 /usr/local/sbin/systemctl
useradd -m tester
mkdir -p /run/dbus /etc/polkit-1/rules.d
dbus-daemon --system --fork
echo 'polkit.addRule(function(action, subject) { polkit.log("ACTION " + action.id); });' > /etc/polkit-1/rules.d/00-lxqtukz-test.rules
## Started before the install, as on a running system.
stdbuf -oL -eL /usr/lib/polkit-1/polkitd >> "${run}/polkitd.log" 2>&1 &
fWaitFor fKnown org.freedesktop.policykit.exec || fDie "polkitd did not start"
fEcho "polkitd $(dpkg-query -W -f='${Version}' polkitd), release ${first}"
mkdir -p /etc/xdg/lxqtukz
printf '%s\n' "AUTO_UPDATE=no" > /etc/xdg/lxqtukz/update.conf

fSection "Install ${old}, then ${first}, with AUTO_UPDATE=no"
fFakeRelease "${old}" distro
fInstall "${run}/fake/lxqtukz-${old}-${TARGET}.tar.gz"
fInstall "${release}"
for unit in lxqtukz-update.service lxqtukz-update.timer; do
	fIf "${unit} linked" fLinksTo "/etc/systemd/system/${unit}" "${ROOT}/current/lib/systemd/system/${unit}"
done
fIf "the timer is off" test ! -e "${WANTS}"
ourAction="org.lxqtukz.backlight-${first}"
fIf "${ourAction} linked into polkit's dir" fLinksTo "${POLKIT_DIR}/${ourAction}.policy" "${ROOT}/versions/${first}/share/polkit-1/actions/${ourAction}.policy"
fWaitFor fKnown "${ourAction}" || true
action="$(fPkexecAction "${ROOT}/versions/${first}")"
if [[ "${action}" == "${ourAction}" ]]; then fCheck "pkexec picks our action for the session's helper" ok; else
	fCheck "pkexec picks our action for the session's helper" fail "${action:-none}"
fi
if pkaction --action-id "${ourAction}" --verbose 2>/dev/null | grep -q 'implicit active: *yes'; then fCheck "an active session needs no password for it" ok; else
	fCheck "an active session needs no password for it" fail
fi
action="$(fPkexecAction /usr/bin/lxqt-backlight_backend)"
if [[ -f "${DISTRO_ACTION}" && ! -L "${DISTRO_ACTION}" && "${action}" == org.lxqt.backlight.pkexec ]]; then fCheck "the distro LXQt's helper keeps its own action" ok; else
	fCheck "the distro LXQt's helper keeps its own action" fail "${action:-none}"
fi

fSection "Turn the timer on later"
fIf "systemctl enable lxqtukz-update.timer" systemctl enable lxqtukz-update.timer
fIf "the timer is on" test "$(readlink -f "${WANTS}")" == "$(readlink -f "${ROOT}/current/lib/systemd/system/lxqtukz-update.timer")"

fSection "Update to ${next}, then ${last}, with KEEP=1"
printf '%s\n' "AUTO_UPDATE=no" "KEEP=1" > /etc/xdg/lxqtukz/update.conf
fFakeRelease "${next}"
fInstall "${run}/fake/lxqtukz-${next}-${TARGET}.tar.gz"
fIf "the timer's unit is still linked" fLinksTo /etc/systemd/system/lxqtukz-update.timer "${ROOT}/current/lib/systemd/system/lxqtukz-update.timer"
fIf "AUTO_UPDATE=no turns the timer off again" test ! -e "${WANTS}"
fWaitFor fKnown "org.lxqtukz.backlight-${next}" || true
action="$(fPkexecAction "${ROOT}/versions/${first}")"
if [[ "${action}" == "${ourAction}" ]]; then fCheck "a session still on ${first} keeps its action" ok; else
	fCheck "a session still on ${first} keeps its action" fail "${action:-none}"
fi
action="$(fPkexecAction "${ROOT}/versions/${next}")"
if [[ "${action}" == "org.lxqtukz.backlight-${next}" ]]; then fCheck "a session on ${next} gets its own" ok; else
	fCheck "a session on ${next} gets its own" fail "${action:-none}"
fi
fFakeRelease "${last}"
fInstall "${run}/fake/lxqtukz-${last}-${TARGET}.tar.gz"
fIf "${old} and ${first} pruned" test ! -e "${ROOT}/versions/${old}" -a ! -e "${ROOT}/versions/${first}"
fIf "its action link went with it" test ! -L "${POLKIT_DIR}/${ourAction}.policy"
fIf "${next} and ${last} still linked" test -e "${POLKIT_DIR}/org.lxqtukz.backlight-${next}.policy" -a -e "${POLKIT_DIR}/org.lxqtukz.backlight-${last}.policy"

fSection "Uninstall"
if bash /src/install.bash --uninstall -y > "${run}/uninstall.log" 2>&1; then fCheck "install.bash --uninstall" ok; else
	sed 's/^/  /' "${run}/uninstall.log"; fCheck "install.bash --uninstall" fail
fi
left="$(find / -xdev \( -path /proc -o -path /sys \) -prune -o -type l -lname "${ROOT}*" -print 2>/dev/null || true)"
if [[ -z "${left}" ]]; then fCheck "no link into ${ROOT} is left" ok; else fCheck "no link into ${ROOT} is left" fail "${left//$'\n'/ }"; fi
fIf "the distro LXQt's action is still there" test -f "${DISTRO_ACTION}"

if ((failed)); then fDie "${failed} check(s) failed"; fi
fEcho "done"


##	History:
##		- 2026-10-15: Created.
