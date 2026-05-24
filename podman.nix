{
  config,
  lib,
  pkgs,
  flakeSelf,
  ...
}: let
  cfg = config.services.hermes-agent-podman;
  inherit (lib) mkOption mkEnableOption mkIf types;

  hermesPkg =
    if cfg.package != null
    then cfg.package
    else (flakeSelf.packages.${pkgs.system}.hermes-agent).withExtras cfg.extras;

  # Build an OCI image containing the hermes venv.
  image = pkgs.dockerTools.buildLayeredImage {
    name = "hermes-agent";
    tag = "nix";
    # Minimal base — bash + coreutils for shell entry points hermes spawns.
    # No git/curl: hermes lazy-installs everything it needs into dataDir.
    contents = [hermesPkg pkgs.bash pkgs.coreutils];
    config = {
      Cmd = ["${hermesPkg}/bin/hermes" "gateway" "run" "--replace" "-v"];
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
  options.services.hermes-agent-podman = {
    enable = mkEnableOption "Run hermes-agent in a podman/docker container via virtualisation.oci-containers";

    backend = mkOption {
      type = types.enum ["podman" "docker"];
      default = "podman";
      description = "Container runtime backend (sets virtualisation.oci-containers.backend).";
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

  config = mkIf cfg.enable {
    virtualisation.oci-containers = {
      backend = cfg.backend;

      containers.${cfg.containerName} = {
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
    };

    # Ensure the bind-mount dir exists with the right ownership before
    # the container starts. UID 10000 matches the upstream Docker image
    # and the bare-metal NixOS module.
    systemd.tmpfiles.rules = [
      "d ${toString cfg.hostDataDir} 0750 10000 10000 -"
    ];
  };
}
