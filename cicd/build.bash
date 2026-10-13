#!/usr/bin/env bash

#  shellcheck disable=2155  ## 'Declare and assign separately to avoid masking return values.' Cumbersome and unnecessary.

##	- Purpose: Builds a Debian LXQtukz release: every pinned component with its
##	  patch queue, into one versioned prefix, then the release assets the
##	  installer and updater download.
##	- Runs in the debian13 container (cicd/linux/Dockerfile) unless --here is
##	  given. Nothing is installed on the host.
##	- The prefix is baked in as /opt/lxqtukz/versions/<version>, which is where
##	  the installer unpacks it. Fixed per version on purpose: LXQt and Wayfire
##	  both compile install paths in, and a fixed path is what lets any number
##	  of versions sit side by side.
##	- Release assets, in cicd/artifacts/release/. install.bash depends on these
##	  names, so change both together:
##	    lxqtukz-<version>-<target>.tar.gz      one top-level dir, '<version>/'
##	    lxqtukz-<version>-<target>-deps.txt    Debian packages it needs at run time
##	    lxqtukz-<version>-sha256sums.txt
##	- Syntax: cicd/build.bash [--here] [--jobs N] [component...]
##	    component...  build only these (into an existing prefix); default all, from clean
##	History: At bottom of script.

##	Copyright © 2026 t00mietum (ID: f⍒Ê🝅ĜᛎỹqFẅ▿⍢Ŷ‡ʬẼᛏ🜣)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=utility/include/echo.bash
source "${REPO_ROOT}/cicd/utility/include/echo.bash"
# shellcheck source=utility/include/components.bash
source "${REPO_ROOT}/cicd/utility/include/components.bash"

fAbort(){ printf "\nBUILD ABORTED (exit %s) at line %s: %s\n\n" "$1" "$2" "$3" >&2; exit "$1"; }
trap 'fAbort $? $LINENO "$BASH_COMMAND"' ERR

IMAGE="lxqtukz-build-debian13"
TARGET="debian13-$(uname -m)"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/version")"
PREFIX="/opt/lxqtukz/versions/${VERSION}"
BUILD_DIR="${REPO_ROOT}/work/build/${TARGET}"
ARTIFACTS="${REPO_ROOT}/cicd/artifacts/release"

declare -i here=0
## Half the cores, so a build leaves the machine usable.
declare -i jobs=$(( $(nproc) / 2 > 0 ? $(nproc) / 2 : 1 ))
only=()
while (($#)); do case "$1" in
	--here) here=1; shift ;;
	--jobs) jobs="${2:?}"; shift 2 ;;
	-h|--help) sed -n '/^##\t- Purpose/,/^##\tHistory/p' "${BASH_SOURCE[0]}" | sed 's/^##\t\{0,1\}//'; exit 0 ;;
	-*) fDie "unknown option: $1" ;;
	*) only+=("$1"); shift ;;
esac; done


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Outside: hand off to the container

if ((! here)); then
	command -v docker >/dev/null || fDie "docker (or podman as docker) is required; or use --here on a Debian 13 box"
	fSection "Build image ${IMAGE}"
	docker build -q -t "${IMAGE}" "${REPO_ROOT}/cicd/linux" >/dev/null
	## Sources are fetched and patched on the host, where git credentials and
	## the mirrors live; the container only compiles.
	fSection "Fetch and apply upstream"
	"${REPO_ROOT}/cicd/upstream.bash" apply "${only[@]+"${only[@]}"}"
	fSection "Build in container"
	exec docker run --rm -i \
		-v "${REPO_ROOT}:/src" -w /src \
		-e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
		"${IMAGE}" /src/cicd/build.bash --here --jobs "${jobs}" "${only[@]+"${only[@]}"}"
fi


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Inside: compile

fComponents_Load
fComponents_Select "${only[@]+"${only[@]}"}"

## A full build starts from an empty prefix, so nothing stale ends up in a release.
if ((${#only[@]} == 0)); then rm -rf "${PREFIX}"; fi
mkdir -p "${PREFIX}" "${BUILD_DIR}"
stamp="$(mktemp)"

export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/share/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
export CMAKE_PREFIX_PATH="${PREFIX}"
export PATH="${PREFIX}/bin:${PATH}"
## Absolute rpath: the prefix is fixed per version, so this always resolves,
## and our libs win over any LXQt the distro also has installed.
rpath="${PREFIX}/lib"

for name in "${selectedComponents[@]}"; do
	srcDir="${REPO_ROOT}/work/src/${name}"; bld="${BUILD_DIR}/${name}"
	[[ -d "${srcDir}" ]] || fDie "${name}: no source tree; run 'cicd/upstream.bash apply ${name}'"
	extra=()
	if [[ -f "${REPO_ROOT}/upstream/flags/${name}" ]]; then
		while read -r line; do [[ -z "${line}" || "${line}" == \#* ]] || extra+=("${line}"); done < "${REPO_ROOT}/upstream/flags/${name}"
	fi
	fSection "${name} ${componentRef[${name}]} (${componentBuild[${name}]})"
	rm -rf "${bld}"
	case "${componentBuild[${name}]}" in
		cmake)
			cmake -S "${srcDir}" -B "${bld}" -G Ninja -Wno-dev \
				-DCMAKE_BUILD_TYPE=Release \
				-DCMAKE_INSTALL_PREFIX="${PREFIX}" \
				-DCMAKE_INSTALL_LIBDIR=lib \
				-DCMAKE_INSTALL_SYSCONFDIR="${PREFIX}/etc" \
				-DCMAKE_INSTALL_RPATH="${rpath}" \
				-DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
				-DLXQT_ETC_XDG_DIR="${PREFIX}/etc/xdg" \
				-DUPDATE_TRANSLATIONS=OFF \
				"${extra[@]+"${extra[@]}"}"
			cmake --build "${bld}" -j "${jobs}"
			cmake --install "${bld}"
			;;
		meson)
			LDFLAGS="-Wl,-rpath,${rpath}" meson setup "${bld}" "${srcDir}" \
				--prefix="${PREFIX}" --libdir=lib --sysconfdir="${PREFIX}/etc" --buildtype=release \
				"${extra[@]+"${extra[@]}"}"
			ninja -C "${bld}" -j "${jobs}"
			meson install -C "${bld}" --quiet
			;;
	esac
done


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Inside: check, stage, package

## Anything a component installed outside the prefix would be missing from the
## release. Lists them instead of guessing a fix; each needs a flag or a patch.
fSection "Check for files installed outside the prefix"
strays="$(find /usr /etc -xdev -newer "${stamp}" -type f 2>/dev/null | grep -v -e '^/etc/ld.so.cache$' -e '/__pycache__/' || true)"
rm -f "${stamp}"
if [[ -n "${strays}" ]]; then
	echo "${strays}" | sed 's/^/  /'
	fDie "components installed files outside ${PREFIX}"
fi
fEcho "none"

commit="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
[[ -z "$(git -C "${REPO_ROOT}" status --porcelain 2>/dev/null)" ]] || commit="${commit}-dirty"
"${REPO_ROOT}/cicd/utility/stage-prefix.bash" "${PREFIX}" "/opt/lxqtukz/current" "${VERSION}" "${commit}" "${TARGET}"

## Partial builds are for iterating; only a full build makes release assets.
((${#only[@]} == 0)) || { fEcho "partial build; no release assets written"; exit 0; }

fSection "Runtime dependencies"
## Every shared library our binaries need that the prefix does not provide,
## mapped to the Debian package that provides it. This is the list the installer
## hands to apt.
deps="$(
	find "${PREFIX}" -type f -exec file --no-pad --separator '|' {} + | awk -F'|' '/ELF/ {print $1}' \
		| xargs -r ldd 2>/dev/null | awk '/=> \// {print $3}' | grep -v "^${PREFIX}/" | sort -u \
		| xargs -r -n1 readlink -f | xargs -r dpkg -S 2>/dev/null | cut -d: -f1 | sort -u
)"
## Run-time programs the session starts by name, which ldd can't see.
deps="$(printf '%s\n' ${deps} dbus-x11 xwayland swaybg | sort -u)"
echo "${deps}" | sed 's/^/  /'

fSection "Package"
mkdir -p "${ARTIFACTS}"
base="lxqtukz-${VERSION}-${TARGET}"
tar -C "$(dirname "${PREFIX}")" -czf "${ARTIFACTS}/${base}.tar.gz" "${VERSION}"
echo "${deps}" > "${ARTIFACTS}/${base}-deps.txt"
## One sums file per version, covering every target built for it so far.
( cd "${ARTIFACTS}" && sha256sum "lxqtukz-${VERSION}-"*.tar.gz "lxqtukz-${VERSION}-"*-deps.txt > "lxqtukz-${VERSION}-sha256sums.txt" )
[[ -z "${HOST_UID:-}" ]] || chown -R "${HOST_UID}:${HOST_GID}" "${ARTIFACTS}" "${REPO_ROOT}/work/build"
ls -l "${ARTIFACTS}" | sed 's/^/  /'


##	History:
##		- 2026-10-12: Created.
