#!/usr/bin/env bash

##	- Purpose: Finishes a prefix that already has every built component:
##	  adds LXQtukz's own files, builds the vendor settings dir, and writes the
##	  release manifest. The Debian build and the Nix package both call this, so
##	  the two install layouts can't drift apart.
##	- Vendor settings, <prefix>/etc/xdg/lxqtukz/, are built in layers:
##	    1. upstream LXQt defaults (<prefix>/share/lxqt/*.conf)
##	    2. upstream's Wayfire config for LXQt, as wayfire.ini
##	    3. our own files from source/etc/xdg/lxqtukz/, which win
##	  Changing a default is therefore either a patch to the upstream file (for
##	  a change worth offering upstream) or a file in source/ (for ours alone).
##	- Syntax: stage-prefix.bash PREFIX EXEC_PREFIX VERSION COMMIT TARGET
##	    PREFIX       the directory to finish (writable)
##	    EXEC_PREFIX  the path the session file should launch from at run time
##	                 (Debian: /opt/lxqtukz/current; Nix: the store path)
##	    VERSION      LXQtukz version
##	    COMMIT       LXQtukz git commit, or 'unknown'
##	    TARGET       build target label, e.g. debian13-x86_64 or nixos
##	History: At bottom of script.

##	Copyright © 2026 t00mietum (CryptogID: ปʬϝღถɔ4რఠΔթะ9ƾǝu)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=include/echo.bash
source "${REPO_ROOT}/cicd/utility/include/echo.bash"
# shellcheck source=include/components.bash
source "${REPO_ROOT}/cicd/utility/include/components.bash"

(($# == 5)) || fDie "usage: stage-prefix.bash PREFIX EXEC_PREFIX VERSION COMMIT TARGET"
prefix="$1"; execPrefix="$2"; version="$3"; commit="$4"; target="$5"
[[ -d "${prefix}" ]] || fDie "no such prefix: ${prefix}"
src="${REPO_ROOT}/source"

## On Nix the prefix is a symlink farm; replace a link before writing through it.
fPlace(){ ## mode source dest
	mkdir -p "$(dirname "$3")"; rm -f "$3"; install -m "$1" "$2" "$3"
}


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Our own files

fPlace 0755 "${src}/bin/startlxqtukz"  "${prefix}/bin/startlxqtukz"
## The installer is the updater; one script, so the two can't disagree.
fPlace 0755 "${REPO_ROOT}/install.bash" "${prefix}/bin/lxqtukz-update"
for unit in "${src}"/lib/systemd/system/*; do
	fPlace 0644 "${unit}" "${prefix}/lib/systemd/system/$(basename "${unit}")"
done
for entry in "${src}"/share/applications/*.desktop; do
	fPlace 0644 "${entry}" "${prefix}/share/applications/$(basename "${entry}")"
done

sessionFile="${prefix}/share/wayland-sessions/lxqtukz.desktop"
mkdir -p "$(dirname "${sessionFile}")"; rm -f "${sessionFile}"
sed "s|@EXEC_PREFIX@|${execPrefix}|g" "${src}/share/wayland-sessions/lxqtukz.desktop" > "${sessionFile}"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Vendor settings

vendor="${prefix}/etc/xdg/lxqtukz"
## Rebuilt from scratch each time, so a removed default goes away.
rm -rf "${vendor}"; mkdir -p "${vendor}"
for conf in "${prefix}"/share/lxqt/*.conf; do
	[[ -e "${conf}" ]] || continue
	cp -L --no-preserve=mode "${conf}" "${vendor}/"
done
upstreamWayfire="${prefix}/share/lxqt/wayland/lxqt-wayfire.ini"
[[ -f "${upstreamWayfire}" ]] || fDie "missing ${upstreamWayfire}; was lxqt-wayland-session built?"
cp -L --no-preserve=mode "${upstreamWayfire}" "${vendor}/wayfire.ini"
cp -RL --no-preserve=mode "${src}/etc/xdg/lxqtukz/." "${vendor}/"

## Only Wayfire is offered, so upstream's compositor chooser has nothing to choose.
if [[ -f "${vendor}/session.conf" ]]; then
	if grep -q '^compositor[[:space:]]*=' "${vendor}/session.conf"; then
		sed -i 's|^compositor[[:space:]]*=.*|compositor=wayfire|' "${vendor}/session.conf"
	else
		sed -i '0,/^\[General\]/s||[General]\ncompositor=wayfire|' "${vendor}/session.conf"
	fi
fi


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Manifest

## What exactly this release is: enough to rebuild it, and what the updater
## and bug reports read back.
fComponents_Load
manifest="${prefix}/share/lxqtukz/manifest"
mkdir -p "$(dirname "${manifest}")"; rm -f "${manifest}"
{
	echo "LXQTUKZ_VERSION=${version}"
	echo "LXQTUKZ_COMMIT=${commit}"
	echo "LXQTUKZ_TARGET=${target}"
	echo "## component ref commit patches"
	for name in "${componentNames[@]}"; do
		echo "COMPONENT ${name} ${componentRef[${name}]} ${componentCommit[${name}]} $(fComponents_Patches "${name}" | grep -c . || true)"
	done
} > "${manifest}"

fEcho "staged ${prefix} (${version}, ${target})"


##	History:
##		- 2026-10-12: Created.
