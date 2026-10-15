## Points each nixpkgs LXQt and Wayfire package at our pinned upstream commit
## with our patch queue, then joins them into one LXQtukz prefix.
##
## Reads upstream/components.conf, upstream/flags/<name> and patches/<name>/series,
## which are the files the Debian build reads too.
{ src, version, commit }:

final: prev:
let
  lib = prev.lib;

  ## Non-blank, non-comment lines of a file, trimmed.
  readLines = file:
    builtins.filter (line: line != "" && !(lib.hasPrefix "#" line))
      (map lib.trim (lib.splitString "\n" (builtins.readFile file)));

  fields = line: builtins.filter (x: builtins.isString x && x != "") (builtins.split "[[:space:]]+" line);

  ## A nix column of - marks a component built on Debian only.
  components = builtins.filter (c: c.attrPath != [ "-" ]) (map (line:
    let f = fields line; in {
      name = builtins.elemAt f 0;
      url = builtins.elemAt f 1;
      ref = builtins.elemAt f 2;
      commit = builtins.elemAt f 3;
      build = builtins.elemAt f 4;
      attrPath = lib.splitString "." (builtins.elemAt f 5);
    }) (readLines "${src}/upstream/components.conf"));

  patchesFor = name:
    let series = "${src}/patches/${name}/series"; in
    if builtins.pathExists series then map (p: "${src}/patches/${name}/${p}") (readLines series) else [ ];

  flagsFor = name:
    let file = "${src}/upstream/flags/${name}"; in
    if builtins.pathExists file then readLines file else [ ];

  ## fetchGit with a rev is allowed in pure evaluation and needs no hash, so a
  ## bump is a one-line change to components.conf and nothing else. Submodules
  ## are wanted: Wayfire builds its pinned wlroots and wf-config from them.
  sourceFor = c: builtins.fetchGit {
    url = c.url;
    rev = c.commit;
    ref = "refs/tags/${c.ref}";
    submodules = true;
  };

  ## Changes that only some components need. Unverified until the first
  ## NixOS build: Wayfire's bundled wlroots needs the system wlroots' inputs.
  tweaks = {
    wayfire = old: {
      buildInputs = (old.buildInputs or [ ]) ++ (final.wlroots.buildInputs or [ ]);
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ (final.wlroots.nativeBuildInputs or [ ]);
    };
  };

  override = c: pkg: pkg.overrideAttrs (old:
    let
      pinnedVersion = lib.removePrefix "v" c.ref;
      ## nixpkgs' own patches are written for nixpkgs' version. Kept only while
      ## that is still the version we pin; past that they are likely stale.
      keepNixpkgsPatches = (old.version or "") == pinnedVersion;
      flagAttr = if c.build == "meson" then "mesonFlags" else "cmakeFlags";
    in {
      version = pinnedVersion;
      src = sourceFor c;
      patches = (if keepNixpkgsPatches then old.patches or [ ] else [ ]) ++ patchesFor c.name;
      ${flagAttr} = (old.${flagAttr} or [ ]) ++ flagsFor c.name;
    } // (tweaks.${c.name} or (_: { })) old);

  inLxqtScope = c: builtins.head c.attrPath == "lxqt";
  scoped = builtins.filter inLxqtScope components;
  topLevel = builtins.filter (c: !(inLxqtScope c)) components;

in
{
  lxqt = prev.lxqt.overrideScope (lfinal: lprev:
    builtins.listToAttrs (map (c:
      let attr = builtins.elemAt c.attrPath 1; in
      { name = attr; value = override c lprev.${attr}; }) scoped));
}
// builtins.listToAttrs (map (c:
  let attr = builtins.head c.attrPath; in
  { name = attr; value = override c prev.${attr}; }) topLevel)
// {
  lxqtukz = final.callPackage ./package.nix {
    inherit src version commit;
    components = map (c: lib.getAttrFromPath c.attrPath final) components;
  };
}
