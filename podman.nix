{
  config,
  lib,
  pkgs,
  flakeSelf,
  ...
}: let
  cfg = config.services.hermes-agent-podman;
  inherit (lib) mkOption mkEnableOption mkIf types;
in {
  options.services.hermes-agent-podman = {
    enable = mkEnableOption "Run hermes-agent in a podman/docker container via virtualisation.oci-containers";

    backend = mkOption {
      type = types.enum ["podman" "docker"];
      default = "podman";
      description = ''
        Container runtime backend. Applied via `mkDefault` so coexisting
        OCI-container modules don't conflict at eval time — explicitly
        override at the host level if needed.
      '';
    };

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = ''
        Hermes-agent package to bundle into the image. Null = derive from
        `extras` via the flake's `withExtras`.
      '';
    };

    extras = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Upstream hermes-agent extras to include.";
    };

    containerName = mkOption {
      type = types.str;
      default = "hermes-agent";
    };

    hostDataDir = mkOption {
      type = types.path;
      default = "/var/lib/hermes-agent";
      description = "Host path bound into the container as /var/lib/hermes-agent.";
    };

    environmentFile = mkOption {
      type = types.path;
      description = "Path to sops-decrypted env dotenv. Loaded via podman --env-file.";
      example = "/run/secrets/hermes-agent";
    };

    apiPort = mkOption {
      type = types.port;
      default = 8642;
    };

    webhookPort = mkOption {
      type = types.port;
      default = 8644;
    };

    openBindAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
    };

    openaiBaseUrl = mkOption {
      type = types.str;
      default = "https://api.openai.com/v1";
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = {};
    };

    autoStart = mkOption {
      type = types.bool;
      default = true;
    };
  };

  config = mkIf cfg.enable (let
    hermesPkg =
      if cfg.package != null
      then cfg.package
      else (flakeSelf.packages.${pkgs.system}.hermes-agent).withExtras cfg.extras;

    # Entry script bridges HERMES_*_BOT_TOKEN to the bare upstream names so
    # the same env file can be shared with notification stacks that already
    # claim TELEGRAM_BOT_TOKEN / DISCORD_BOT_TOKEN. Mirrors module.nix.
    entry = pkgs.writeShellScript "hermes-entry" ''
      #!/usr/bin/env bash
      set -euo pipefail
      if [ -n "''${HERMES_TELEGRAM_BOT_TOKEN:-}" ]; then
        export TELEGRAM_BOT_TOKEN="$HERMES_TELEGRAM_BOT_TOKEN"
      fi
      if [ -n "''${HERMES_DISCORD_BOT_TOKEN:-}" ]; then
        export DISCORD_BOT_TOKEN="$HERMES_DISCORD_BOT_TOKEN"
      fi
      exec ${hermesPkg}/bin/hermes gateway run --replace -v
    '';

    image = pkgs.dockerTools.buildLayeredImage {
      name = "hermes-agent";
      tag = "nix";
      # copyToRoot + fakeNss gives a proper /etc/passwd + /etc/group so
      # UID 10000 (the bundled service user) resolves inside the container
      # for `pwd.getpwuid()` callers (Python tempfile, subprocess, etc.).
      copyToRoot = pkgs.buildEnv {
        name = "hermes-image-root";
        paths = [
          hermesPkg
          entry
          pkgs.bash
          pkgs.coreutils
          pkgs.dockerTools.fakeNss
        ];
        pathsToLink = ["/bin" "/etc"];
      };
      config = {
        Cmd = ["${entry}"];
        Env = [
          "HERMES_HOME=/var/lib/hermes-agent"
          "API_SERVER_ENABLED=true"
          "API_SERVER_HOST=${cfg.openBindAddress}"
          "API_SERVER_PORT=${toString cfg.apiPort}"
          "WEBHOOK_ENABLED=true"
          "WEBHOOK_PORT=${toString cfg.webhookPort}"
          "OPENAI_BASE_URL=${cfg.openaiBaseUrl}"
        ];
        ExposedPorts = {
          "${toString cfg.apiPort}/tcp" = {};
          "${toString cfg.webhookPort}/tcp" = {};
        };
        Volumes = {
          "/var/lib/hermes-agent" = {};
        };
      };
    };
  in {
    # mkDefault so a coexisting oci-containers module can win without
    # blowing up at eval time.
    virtualisation.oci-containers.backend = lib.mkDefault cfg.backend;

    virtualisation.oci-containers.containers.${cfg.containerName} = {
      imageFile = image;
      image = "hermes-agent:nix";
      autoStart = cfg.autoStart;

      environment = cfg.extraEnvironment;
      environmentFiles = [cfg.environmentFile];

      ports = [
        "${cfg.openBindAddress}:${toString cfg.apiPort}:${toString cfg.apiPort}"
        "${cfg.openBindAddress}:${toString cfg.webhookPort}:${toString cfg.webhookPort}"
      ];

      volumes = [
        "${toString cfg.hostDataDir}:/var/lib/hermes-agent:rw"
      ];

      # Default ports are 8642/8644 (>1024) — no NET_BIND_SERVICE needed.
      # Add it explicitly if you reconfigure to a privileged port.
      extraOptions = [
        "--read-only"
        "--tmpfs=/tmp"
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges"
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${toString cfg.hostDataDir} 0750 10000 10000 -"
    ];
  });
}
