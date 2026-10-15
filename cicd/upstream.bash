#!/usr/bin/env bash

#  shellcheck disable=2155  ## 'Declare and assign separately to avoid masking return values.' Cumbersome and unnecessary.

##	- Purpose: Upstream tracking for LXQtukz. Each component is an upstream repo
##	  pinned to a release (upstream/components.conf) plus our patch queue
##	  (patches/<component>/). This turns the pair into a working tree, turns a
##	  working tree back into a queue, and moves a pin by rebasing the queue.
##	- Subcommands:
##	    status  [component...]       pin, queue size, newest upstream release, tree state
##	    fetch   [component...]       clone or update the local upstream mirrors
##	    apply   [component...]       recreate work/src/<component>: the pin plus the queue
##	    refresh  component...        write work/src/<component> commits back into the queue
##	    bump     component REF       rebase the queue onto upstream REF and move the pin
##	    bump     component --continue
##	                                 finish a bump after resolving its rebase by hand
##	- Editing a patch: apply, then commit (or rebase -i) in work/src/<component>
##	  on its 'lxqtukz' branch, then refresh, then commit the repo. The commit
##	  message of each work-tree commit becomes the patch's description.
##	- apply refuses to discard a work tree that has changes the queue doesn't
##	  have yet. --force overrides that.
##	- Syntax: cicd/upstream.bash <subcommand> [args] [--force]
##	History: At bottom of script.

##	Copyright © 2026 t00mietum (CryptogID: ปʬϝღถɔ4რఠΔթะ9ƾǝu)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${REPO_ROOT}/work"
MIRROR_DIR="${WORK_DIR}/mirror"
SRC_DIR="${WORK_DIR}/src"
BRANCH="lxqtukz"

# shellcheck source=utility/include/echo.bash
source "${REPO_ROOT}/cicd/utility/include/echo.bash"
# shellcheck source=utility/include/components.bash
source "${REPO_ROOT}/cicd/utility/include/components.bash"

fAbort(){ printf "\nABORTED (exit %s) at line %s: %s\n\n" "$1" "$2" "$3" >&2; exit "$1"; }
trap 'fAbort $? $LINENO "$BASH_COMMAND"' ERR

## am and rebase need an identity even though the queue zeroes it out on export.
## Only supplied when the user has none, so real authorship is kept when set.
git config user.email >/dev/null 2>&1 || export GIT_COMMITTER_NAME="LXQtukz" GIT_COMMITTER_EMAIL="lxqtukz@localhost" GIT_AUTHOR_NAME="LXQtukz" GIT_AUTHOR_EMAIL="lxqtukz@localhost"


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Helpers

fMirror(){ echo "${MIRROR_DIR}/$1.git"; }
fTree(){   echo "${SRC_DIR}/$1"; }

## Newest release-looking tag upstream, with the same prefix as the pin, such
## as 'v' or 'libdrm-'. Pre-releases and odd tags (e.g. pcmanfm-qt's
## 'split-libfm-qt') are left out on purpose. Empty when none match.
fNewestUpstreamTag(){
	local prefix="${componentRef[$1]%%[0-9]*}"
	git ls-remote --tags --refs "${componentUrl[$1]}" 2>/dev/null \
		| sed 's|.*refs/tags/||' | grep -E "^${prefix//./\\.}[0-9]+(\.[0-9]+)+$" | sort -V | tail -1 || true
}

## Same flags as refresh, so a tree and its queue compare byte for byte.
fExportQueue(){
	local name="$1" outDir="$2" tree="$(fTree "$1")"
	git -C "${tree}" format-patch --quiet --zero-commit --no-signature --no-numbered --full-index \
		-o "${outDir}" "${componentCommit[${name}]}..${BRANCH}" >/dev/null
	( cd "${outDir}" && find . -maxdepth 1 -name '*.patch' -printf '%f\n' | sort ) > "${outDir}/series"
	## No series file for an empty queue.
	[[ -s "${outDir}/series" ]] || rm -f "${outDir}/series"
}

## 0 = tree matches the queue, 1 = it has something else, 2 = no tree.
fTreeMatchesQueue(){
	local name="$1" tree="$(fTree "$1")" tmp
	[[ -d "${tree}" ]] || return 2
	[[ -z "$(git -C "${tree}" status --porcelain)" ]] || return 1
	git -C "${tree}" rev-parse -q --verify "refs/heads/${BRANCH}" >/dev/null || return 1
	tmp="$(mktemp -d)"
	fExportQueue "${name}" "${tmp}"
	local -i rc=0
	diff -rq -x README.md "${tmp}" "${PATCHES_DIR}/${name}" >/dev/null 2>&1 || rc=1
	## An empty queue has no dir at all on one side.
	if ((rc)) && [[ ! -d "${PATCHES_DIR}/${name}" ]] && [[ -z "$(ls -A "${tmp}")" ]]; then rc=0; fi
	rm -rf "${tmp}"
	return ${rc}
}


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Subcommands

fFetch(){
	local name mirror
	mkdir -p "${MIRROR_DIR}"
	for name in "$@"; do
		mirror="$(fMirror "${name}")"
		if [[ -d "${mirror}" ]]; then
			fEcho "fetch ${name}"
			git -C "${mirror}" fetch --quiet --tags --force origin '+refs/heads/*:refs/heads/*'
		else
			fEcho "clone ${name}"
			git clone --quiet --bare "${componentUrl[${name}]}" "${mirror}"
		fi
	done
}

fApply(){
	local name mirror tree pinned resolved patch
	local -i rc
	for name in "$@"; do
		mirror="$(fMirror "${name}")"; tree="$(fTree "${name}")"; pinned="${componentCommit[${name}]}"
		[[ -d "${mirror}" ]] || fFetch "${name}"

		## Catches a tag that was moved upstream after we pinned it.
		resolved="$(git -C "${mirror}" rev-parse -q --verify "refs/tags/${componentRef[${name}]}^{commit}" || true)"
		[[ "${resolved}" == "${pinned}" ]] || fDie "${name}: tag ${componentRef[${name}]} is ${resolved:-missing} upstream, but pinned as ${pinned}"

		rc=0; fTreeMatchesQueue "${name}" || rc=$?
		if ((rc == 1)) && ((! force)); then
			fDie "${name}: work tree has changes not in the queue. Run 'refresh ${name}' to keep them, or --force to drop them."
		fi
		if [[ -d "${tree}" ]]; then
			git -C "${mirror}" worktree remove --force "${tree}"
		fi
		git -C "${mirror}" worktree prune

		fEcho "apply ${name} @ ${componentRef[${name}]}"
		mkdir -p "${SRC_DIR}"
		git -C "${mirror}" worktree add --quiet --force -B "${BRANCH}" "${tree}" "${pinned}"
		if [[ -f "${tree}/.gitmodules" ]]; then
			git -C "${tree}" submodule update --quiet --init --recursive
		fi
		while read -r patch; do
			[[ -n "${patch}" ]] || continue
			git -C "${tree}" am --quiet --no-3way --keep-cr "${patch}" \
				|| fDie "${name}: $(basename "${patch}") no longer applies. Fix it in ${tree} ('git am --show-current-patch'), then 'git am --continue' and refresh."
		done < <(fComponents_Patches "${name}")
		fEcho_Clean "  $(git -C "${tree}" rev-list --count "${pinned}..HEAD") patch(es) applied"
	done
}

fRefresh(){
	local name tree dir tmp
	for name in "$@"; do
		tree="$(fTree "${name}")"; dir="${PATCHES_DIR}/${name}"
		[[ -d "${tree}" ]] || fDie "${name}: no work tree; run 'apply ${name}' first"
		[[ -z "$(git -C "${tree}" status --porcelain)" ]] || fDie "${name}: commit or stash work-tree changes first; refresh only exports commits"
		[[ "$(git -C "${tree}" rev-parse --abbrev-ref HEAD)" == "${BRANCH}" ]] || fDie "${name}: work tree is not on branch ${BRANCH}"
		git -C "${tree}" merge-base --is-ancestor "${componentCommit[${name}]}" HEAD || fDie "${name}: ${BRANCH} is not based on the pinned commit"

		tmp="$(mktemp -d)"
		fExportQueue "${name}" "${tmp}"
		mkdir -p "${dir}"
		find "${dir}" -maxdepth 1 \( -name '*.patch' -o -name series \) -delete
		if [[ -n "$(ls -A "${tmp}")" ]]; then cp "${tmp}"/* "${dir}/"; fi
		rm -rf "${tmp}"
		## Keep a dir that has a README; drop one that would be empty.
		rmdir "${dir}" 2>/dev/null || true
		fEcho "refresh ${name}: $(find "${dir}" -maxdepth 1 -name '*.patch' 2>/dev/null | wc -l) patch(es) in queue"
	done
}

fStatus(){
	local name newest state count
	local -i rc
	printf "%-24s %-18s %-18s %-6s %s\n" "component" "pinned" "upstream" "queue" "work tree"
	for name in "$@"; do
		newest="$(fNewestUpstreamTag "${name}")"
		count="$(fComponents_Patches "${name}" | grep -c . || true)"
		rc=0; fTreeMatchesQueue "${name}" || rc=$?
		case ${rc} in 0) state="clean" ;; 1) state="CHANGED - refresh or --force apply" ;; *) state="-" ;; esac
		[[ "${newest}" == "${componentRef[${name}]}" ]] || newest="${newest:-?} *"
		printf "%-24s %-18s %-18s %-6s %s\n" "${name}" "${componentRef[${name}]}" "${newest}" "${count}" "${state}"
	done
	fEcho_Clean ""
	fEcho_Clean "* = newer upstream release than the pin; 'bump <component> <tag>' moves to it."
}

## Rewrites one row of components.conf, keeping comments and column layout.
fWritePin(){
	local name="$1" ref="$2" commit="$3" tmp="$(mktemp)"
	awk -v n="${name}" -v r="${ref}" -v c="${commit}" '
		$1 == n && $1 !~ /^#/ { printf "%-24s %-50s %-9s %s  %-6s %s\n", $1, $2, r, c, $5, $6; next }
		{ print }
	' "${COMPONENTS_CONF}" > "${tmp}"
	cat "${tmp}" > "${COMPONENTS_CONF}"; rm -f "${tmp}"
}

fBumpStateFile(){ echo "${WORK_DIR}/bump-$1"; }

fBumpFinish(){
	local name="$1" newRef="$2" newCommit="$3" tree="$(fTree "$1")"
	git -C "${tree}" merge-base --is-ancestor "${newCommit}" HEAD || fDie "${name}: ${BRANCH} is not on top of ${newRef} yet"
	fWritePin "${name}" "${newRef}" "${newCommit}"
	componentRef[${name}]="${newRef}"; componentCommit[${name}]="${newCommit}"
	fRefresh "${name}"
	rm -f "$(fBumpStateFile "${name}")"
	fEcho "bump ${name}: now ${newRef}. Review 'git diff', note it in changelog.md, then commit."
}

fBump(){
	local name="$1" arg="${2:-}" mirror tree newCommit oldCommit stateFile
	[[ -n "${arg}" ]] || fDie "usage: bump <component> <upstream-tag> | --continue"
	mirror="$(fMirror "${name}")"; tree="$(fTree "${name}")"; stateFile="$(fBumpStateFile "${name}")"

	if [[ "${arg}" == "--continue" ]]; then
		[[ -f "${stateFile}" ]] || fDie "${name}: no bump in progress"
		[[ ! -d "$(git -C "${tree}" rev-parse --git-path rebase-merge)" && ! -d "$(git -C "${tree}" rev-parse --git-path rebase-apply)" ]] \
			|| fDie "${name}: rebase still in progress; finish it with 'git rebase --continue' in ${tree}"
		# shellcheck disable=1090
		source "${stateFile}"
		fBumpFinish "${name}" "${BUMP_REF}" "${BUMP_COMMIT}"
		return 0
	fi

	[[ ! -f "${stateFile}" ]] || fDie "${name}: a bump is already in progress; use --continue"
	fFetch "${name}"
	newCommit="$(git -C "${mirror}" rev-parse -q --verify "refs/tags/${arg}^{commit}" || true)"
	[[ -n "${newCommit}" ]] || fDie "${name}: no upstream tag '${arg}'"
	oldCommit="${componentCommit[${name}]}"
	[[ "${newCommit}" != "${oldCommit}" ]] || fDie "${name}: already pinned to ${arg}"

	fApply "${name}"
	printf 'BUMP_REF=%q\nBUMP_COMMIT=%q\n' "${arg}" "${newCommit}" > "${stateFile}"
	fEcho "rebase ${name} queue: ${componentRef[${name}]} -> ${arg}"
	if ! git -C "${tree}" rebase --quiet --onto "${newCommit}" "${oldCommit}" "${BRANCH}"; then
		fEcho_Clean ""
		fEcho_Clean "Conflicts. Resolve them in ${tree} and run 'git rebase --continue' there,"
		fEcho_Clean "then: cicd/upstream.bash bump ${name} --continue"
		exit 1
	fi
	fBumpFinish "${name}" "${arg}" "${newCommit}"
}

## A moved repo leaves each work tree pointing at its mirror by the old
## absolute path. git then can't see the tree, and the prune in apply would
## drop it, so this runs before any subcommand.
fTrees_Repair(){
	local tree name gitdir
	for tree in "${SRC_DIR}"/*/; do
		tree="${tree%/}"; name="${tree##*/}"
		[[ -f "${tree}/.git" ]] || continue
		gitdir="$(sed -n 's/^gitdir: //p' "${tree}/.git")"
		[[ ! -d "${gitdir}" ]] || continue
		[[ -d "$(fMirror "${name}")" ]] || continue
		fEcho "repair ${name}: the repo moved"
		git -C "$(fMirror "${name}")" worktree repair "${tree}"
	done
}

fHelp(){ sed -n '/^##\t- Purpose/,/^##\tHistory/p' "${BASH_SOURCE[0]}" | sed 's/^##\t\{0,1\}//'; }


#••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
# Main

declare -i force=0
args=()
for arg in "$@"; do case "${arg}" in
	--force) force=1 ;;
	-h|--help) fHelp; exit 0 ;;
	*) args+=("${arg}") ;;
esac; done
set -- "${args[@]+"${args[@]}"}"

(($#)) || { fHelp; exit 1; }
subcommand="$1"; shift
fComponents_Load
fTrees_Repair

case "${subcommand}" in
	status)  fComponents_Select "$@"; fStatus  "${selectedComponents[@]}" ;;
	fetch)   fComponents_Select "$@"; fFetch   "${selectedComponents[@]}" ;;
	apply)   fComponents_Select "$@"; fApply   "${selectedComponents[@]}" ;;
	refresh) (($#)) || fDie "refresh needs component names (it rewrites the queue)"
	         fComponents_Select "$@"; fRefresh "${selectedComponents[@]}" ;;
	bump)    (($# == 2)) || fDie "usage: bump <component> <upstream-tag> | --continue"
	         fComponents_Select "$1"; fBump "$1" "$2" ;;
	*) fDie "unknown subcommand: ${subcommand} (try --help)" ;;
esac


##	History:
##		- 2026-10-12: Created.
##		- 2026-10-15: Work trees left behind by a moved repo are repaired.
##		- 2026-10-15: status matches tags with the pin's prefix, and no longer stops on a component with none.
