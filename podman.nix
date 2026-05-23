{
  config,
  lib,
  pkgs,
  flakeSelf,
  ...
}: let
  cfg = config.services.hermes-agent-podman;
  inherit (lib) mkOption mkEnableOption mkIf types;
  shared = import ./nixos/wrapper-options.nix {inherit lib pkgs;};
in {
  options.services.hermes-agent-podman =
    shared.options
    // {
      enable = mkEnableOption "Run hermes-agent in a podman/docker container via virtualisation.oci-containers";

      backend = mkOption {
        type = types.enum ["podman" "docker"];
        default = "podman";
        description = ''
          Container runtime backend. Applied via `mkDefault` so coexisting
          OCI-container modules don't conflict at eval time.
        '';
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

    # Entry bridges HERMES_*_BOT_TOKEN to bare upstream names. writeShellScript
    # already emits the absolute-store-path shebang — the user-visible body
    # below must NOT start with another shebang line.
    entry = pkgs.writeShellScript "hermes-entry" ''
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
      # fakeNss → /etc/passwd, /etc/group, /etc/nsswitch.conf so UID 10000
      # resolves inside the container.
      copyToRoot = pkgs.buildEnv {
        name = "hermes-image-root";
        paths = [hermesPkg pkgs.bash pkgs.coreutils pkgs.dockerTools.fakeNss];
        pathsToLink = ["/bin" "/etc"];
      };
      # entry script's closure is pulled in automatically because Cmd
      # references its absolute store path; no need to put it on PATH.
      config = {
        Cmd = ["${entry}"];
        Env =
          [
            "HERMES_HOME=/var/lib/hermes-agent"
            "API_SERVER_ENABLED=true"
            "WEBHOOK_ENABLED=true"
          ]
          ++ lib.optional (cfg.maxIterations != 90) "HERMES_MAX_ITERATIONS=${toString cfg.maxIterations}"
          ++ lib.optional (cfg.profile != null) "HERMES_PROFILE=${cfg.profile}"
          ++ lib.optional cfg.enableDashboard "HERMES_DASHBOARD=1"
          ++ lib.optional cfg.enableDashboard "HERMES_DASHBOARD_HOST=${cfg.dashboardHost}"
          ++ lib.optional cfg.enableDashboard "HERMES_DASHBOARD_PORT=${toString cfg.dashboardPort}";
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
    virtualisation.oci-containers.backend = lib.mkDefault cfg.backend;

    virtualisation.oci-containers.containers.${cfg.containerName} = {
      imageFile = image;
      image = "hermes-agent:nix";
      autoStart = cfg.autoStart;

      # Runtime-injected env. These OVERRIDE the image-baked Env at runtime
      # per OCI semantics, so bind/port changes don't require an image
      # rebuild as long as the Nix derivation hash changes (which it does
      # for any cfg change).
      environment =
        {
          API_SERVER_HOST = cfg.openBindAddress;
          API_SERVER_PORT = toString cfg.apiPort;
          WEBHOOK_PORT = toString cfg.webhookPort;
          OPENAI_BASE_URL = cfg.openaiBaseUrl;
        }
        // (lib.optionalAttrs (cfg.telegramAllowedUsers != []) {
          TELEGRAM_ALLOWED_USERS =
            lib.concatMapStringsSep "," toString cfg.telegramAllowedUsers;
        })
        // (lib.optionalAttrs (cfg.telegramAllowedChats != []) {
          TELEGRAM_ALLOWED_CHATS = lib.concatStringsSep "," cfg.telegramAllowedChats;
        })
        // (lib.optionalAttrs (cfg.telegramAllowedTopics != []) {
          TELEGRAM_ALLOWED_TOPICS = lib.concatStringsSep "," cfg.telegramAllowedTopics;
        })
        // (lib.optionalAttrs (cfg.apiServerCorsOrigins != []) {
          API_SERVER_CORS_ORIGINS = lib.concatStringsSep "," cfg.apiServerCorsOrigins;
        })
        // (lib.optionalAttrs (cfg.apiServerModelName != "") {
          API_SERVER_MODEL_NAME = cfg.apiServerModelName;
        })
        // cfg.extraEnvironment;

      environmentFiles = [cfg.environmentFile];

      ports = [
        "${cfg.openBindAddress}:${toString cfg.apiPort}:${toString cfg.apiPort}"
        "${cfg.openBindAddress}:${toString cfg.webhookPort}:${toString cfg.webhookPort}"
      ];

      volumes = [
        "${toString cfg.hostDataDir}:/var/lib/hermes-agent:rw"
      ];

      # Default ports are 8642/8644 (>1024) — no NET_BIND_SERVICE needed.
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
