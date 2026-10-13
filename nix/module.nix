## NixOS module: services.lxqtukz.
##
## System settings go in /etc/xdg/lxqtukz/, the same place as on Debian, but
## written from services.lxqtukz.settings rather than by hand.
{ self }:

{ config, lib, pkgs, ... }:

let
  cfg = config.services.lxqtukz;
  inherit (lib) mkOption mkEnableOption mkIf types;

  updateConf = pkgs.writeText "lxqtukz-update.conf" ''
    AUTO_UPDATE=${if cfg.autoUpdate.enable then "yes" else "no"}
    CHANNEL=${cfg.autoUpdate.channel}
    PIN=${if cfg.autoUpdate.pin == null then "" else cfg.autoUpdate.pin}
    FLAKE=${cfg.autoUpdate.flake}
    NIXOS_REBUILD=${cfg.autoUpdate.operation}
  '';
in
{
  options.services.lxqtukz = {
    enable = mkEnableOption "the LXQtukz desktop (LXQt on Wayfire)";

    package = mkOption {
      type = types.package;
      default = pkgs.lxqtukz;
      defaultText = lib.literalExpression "pkgs.lxqtukz";
      description = "The joined LXQtukz prefix.";
    };

    settings = mkOption {
      type = types.attrsOf (types.either types.path types.lines);
      default = { };
      example = lib.literalExpression ''{ "wayfire.ini" = ./wayfire.ini; "panel.conf" = "[General]\n..."; }'';
      description = ''
        Files for the system settings area, /etc/xdg/lxqtukz/, by name. Each
        shadows the release's default of the same name; users' own copies in
        ~/.config/lxqtukz/ still win over these.
      '';
    };

    autoUpdate = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Re-lock the system flake's lxqtukz input to new releases on a timer.";
      };
      channel = mkOption {
        type = types.enum [ "stable" "dev" ];
        default = "stable";
        description = "stable takes full releases only; dev also takes pre-releases.";
      };
      pin = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "0.3.1";
        description = "Stay on exactly this version, older or newer than the current one.";
      };
      flake = mkOption {
        type = types.str;
        default = "/etc/nixos";
        description = "Directory of the system flake that has the 'lxqtukz' input.";
      };
      operation = mkOption {
        type = types.enum [ "boot" "switch" ];
        default = "boot";
        description = "boot applies an update at next reboot; switch applies it at once.";
      };
      dates = mkOption {
        type = types.str;
        default = "daily";
        description = "systemd OnCalendar expression for the update check.";
      };
    };
  };

  config = mkIf cfg.enable {
    nixpkgs.overlays = [ self.overlays.default ];

    environment.systemPackages = [ cfg.package ];
    services.displayManager.sessionPackages = [ cfg.package ];

    environment.etc = {
      ## Read by lxqtukz-update --status to report the active version.
      "xdg/lxqtukz/manifest".source = "${cfg.package}/share/lxqtukz/manifest";
      "xdg/lxqtukz/update.conf".source = updateConf;
    } // lib.mapAttrs' (name: value: lib.nameValuePair "xdg/lxqtukz/${name}"
      (if builtins.isPath value || lib.isStorePath value then { source = value; } else { text = value; }))
      cfg.settings;

    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.lxqt.xdg-desktop-portal-lxqt ];
    };
    security.polkit.enable = true;
    hardware.graphics.enable = lib.mkDefault true;
    programs.xwayland.enable = lib.mkDefault true;
    services.upower.enable = lib.mkDefault true;

    systemd.services.lxqtukz-update = mkIf cfg.autoUpdate.enable {
      description = "LXQtukz automatic update";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [ config.nix.package config.system.build.nixos-rebuild pkgs.curl pkgs.gawk pkgs.gnused pkgs.gnugrep pkgs.coreutils pkgs.git ];
      serviceConfig = { Type = "oneshot"; Nice = 10; IOSchedulingClass = "idle"; };
      script = "${cfg.package}/bin/lxqtukz-update --auto";
    };

    systemd.timers.lxqtukz-update = mkIf cfg.autoUpdate.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = { OnCalendar = cfg.autoUpdate.dates; Persistent = true; RandomizedDelaySec = "1h"; };
    };
  };
}
