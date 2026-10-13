<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Upstream provenance

LXQtukz is built from LXQt and Wayfire releases, with its own changes as patches on top. It keeps following new upstream releases.

- LXQt: <https://github.com/lxqt>, one repository per component.

- Wayfire: <https://github.com/WayfireWM/wayfire>

- What's pinned, to which release and commit: `upstream/components.conf`

- What we change: `patches/<component>/`, applied in the order of each `series` file.

Upstream source isn't copied into this repository. It's fetched at the pinned commit, and every apply checks the pin against the tag.

## How tracking works

- Each component is pinned to an upstream release tag. `cicd/upstream.bash status` shows when upstream has a newer one.

- `cicd/upstream.bash bump <component> <tag>` rebases our patches onto the new release. Patches that upstream has since taken drop out. A conflict gets fixed once, in the patch, instead of again in every merge.

- If a component's changes get too big for a patch queue, it can move to a fork under t00mietum. Its `url` in `components.conf` changes, and the rest of the tooling stays the same.

- Changes that would help upstream are written so they can be sent upstream as-is, and should be. Anything upstream takes drops out of our queue.

## Affiliation

LXQtukz is not affiliated with, endorsed by, or supported by the LXQt project or the WayfireWM project. "LXQt" and "Wayfire" belong to their respective owners. Direct all issues and support requests to this repository.

## License

Patches to a component are under that component's license, which for most of LXQt is LGPL-2.1-or-later. LXQtukz's own desktop code is LGPL-2.1-or-later, in `license.txt`. Build and helper scripts are MIT, per their headers.

## Marking changes

LGPL-2.1 and GPL-2.0 section 2a ask for modified files to say so. Files a patch changes in a real way get a short notice with what changed and when, e.g.:

~~~c
/* Modified 2026 for LXQtukz: configurable configuration directory name. */
~~~

The patch queue and also its commit messages are the full record of what changed and why.
