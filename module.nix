{
  config,
  lib,
  pkgs,
  flakePackages,
  ...
}: let
  cfg = config.services.hermes-agent;
  inherit (lib) mkOption mkEnableOption mkIf types optional optionalString;

  defaultConfigFile = import ./config.yaml.nix {
    inherit pkgs lib;
    settings = cfg.settings;
  };

  configFile =
    if cfg.configFile != null
    then cfg.configFile
    else defaultConfigFile;

  soulFile =
    if cfg.soulFile != null
    then cfg.soulFile
    else ./SOUL.md;

  bootstrapScript = pkgs.writeShellScript "hermes-bootstrap" ''
    set -euo pipefail

    # btrfs subvolume bootstrap — idempotent
    if [ ! -d "${cfg.dataDir}" ]; then
      # If parent FS is btrfs, prefer subvolume for snapshot support.
      # Falls back to plain mkdir otherwise.
      parent=$(${pkgs.coreutils}/bin/dirname "${cfg.dataDir}")
      fstype=$(${pkgs.util-linux}/bin/findmnt -no FSTYPE "$parent" 2>/dev/null || echo "")
      if [ "$fstype" = "btrfs" ]; then
        ${pkgs.btrfs-progs}/bin/btrfs subvolume create "${cfg.dataDir}"
      else
        ${pkgs.coreutils}/bin/mkdir -p "${cfg.dataDir}"
      fi
    fi

    ${pkgs.coreutils}/bin/chown -R ${cfg.user}:${cfg.group} "${cfg.dataDir}"
    ${pkgs.coreutils}/bin/chmod 0750 "${cfg.dataDir}"

    # Stage config + SOUL into dataDir (mutable, so hermes can edit if needed)
    ${pkgs.coreutils}/bin/install -m 0640 -o ${cfg.user} -g ${cfg.group} \
      ${configFile} "${cfg.dataDir}/config.yaml"
    ${pkgs.coreutils}/bin/install -m 0640 -o ${cfg.user} -g ${cfg.group} \
      ${soulFile} "${cfg.dataDir}/SOUL.md"
  '';
in {
  options.services.hermes-agent = {
    enable = mkEnableOption "Hermes Agent (NousResearch) — homelab system service";

    package = mkOption {
      type = types.package;
      default = flakePackages.${pkgs.system}.hermes-agent;
      defaultText = "hermes-flake.packages.\${system}.hermes-agent";
      description = "Hermes-agent package to run.";
    };

    user = mkOption {
      type = types.str;
      default = "hermes";
      description = "Run user. UID 10000 to match migrated volumes from Docker.";
    };

    group = mkOption {
      type = types.str;
      default = "hermes";
      description = "Run group. GID 10000 to match migrated volumes from Docker.";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/hermes-agent";
      description = ''
        Persistent state dir (memory, skills, sessions, lazy-installed venv).
        SHOULD be a btrfs subvolume for snapshot support — bootstrap creates
        the subvolume automatically if the parent FS is btrfs.

        Hermes writes its mutable Python venv into this dir (via HERMES_HOME),
        which is required because the nix store is read-only and Hermes
        lazy-installs heavy deps (telegram, discord voice, playwright) on
        first use.
      '';
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to a sops-decrypted dotenv file containing required secrets:
        LITELLM_API_KEY, OPENAI_API_KEY, OPENROUTER_API_KEY, API_SERVER_KEY,
        HERMES_TELEGRAM_BOT_TOKEN, HERMES_DISCORD_BOT_TOKEN, EXA_API_KEY.

        Set this to `config.sops.secrets."hermes-agent/env".path` after
        defining the secret via sops-nix.
      '';
      example = "/run/secrets/hermes-agent";
    };

    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Optional override path to a hermes config.yaml. If null, the module
        generates one from `services.hermes-agent.settings`.
      '';
    };

    settings = mkOption {
      type = types.attrs;
      default = {};
      description = ''
        Hermes config.yaml content as a Nix attrset, rendered via pkgs.formats.yaml.
        Merges recursively with the homelab-tuned default in config.yaml.nix.
      '';
      example = lib.literalExpression ''
        {
          agent.max_turns = 120;
          model.default = "claude-opus-4-7";
        }
      '';
    };

    soulFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to a SOUL.md personality file. Defaults to the flake's bundled
        homelab personality.
      '';
    };

    openBindAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = ''
        Bind address for the API server. Defaults to 0.0.0.0 so reverse proxies
        (SWAG) can reach it. When NOT localhost, the env var `API_SERVER_KEY`
        is required (set via environmentFile).
      '';
    };

    apiPort = mkOption {
      type = types.port;
      default = 8642;
      description = "Port for hermes api_server gateway.";
    };

    webhookPort = mkOption {
      type = types.port;
      default = 8644;
      description = "Port for hermes webhook gateway.";
    };

    telegramAllowedUsers = mkOption {
      type = types.listOf types.int;
      default = [];
      description = "Telegram user IDs allowed to message the agent (env TELEGRAM_ALLOWED_USERS).";
      example = [7729797827];
    };

    telegramAllowedChats = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Telegram group chat IDs allowed (env TELEGRAM_ALLOWED_CHATS).";
      example = ["-1001234567890"];
    };

    telegramAllowedTopics = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Telegram forum topic IDs allowed (env TELEGRAM_ALLOWED_TOPICS).";
    };

    openaiBaseUrl = mkOption {
      type = types.str;
      default = "https://litellm.homelab.pastelariadev.com/v1";
      description = "OPENAI_BASE_URL — typically your LiteLLM proxy.";
    };

    apiServerCorsOrigins = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "CORS allow-origins for the API server (env API_SERVER_CORS_ORIGINS, comma-joined).";
      example = ["https://hermes.example.com"];
    };

    apiServerModelName = mkOption {
      type = types.str;
      default = "";
      description = "Override model name for API server requests (env API_SERVER_MODEL_NAME).";
    };

    maxIterations = mkOption {
      type = types.int;
      default = 90;
      description = ''
        HERMES_MAX_ITERATIONS — per API-server request iteration cap.
        Separate from agent.max_turns (which governs chat turns).
      '';
    };

    enableDashboard = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Run the hermes web dashboard (port 9119 by default) alongside the gateway.
        Sets HERMES_DASHBOARD=1. Bind via dashboardHost / dashboardPort.
      '';
    };

    dashboardHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Dashboard bind addr (HERMES_DASHBOARD_HOST).";
    };

    dashboardPort = mkOption {
      type = types.port;
      default = 9119;
      description = "Dashboard port (HERMES_DASHBOARD_PORT).";
    };

    profile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Hermes profile name (HERMES_PROFILE). Enables running multiple isolated
        gateway profiles from the same dataDir.
      '';
    };

    memoryMax = mkOption {
      type = types.str;
      default = "2G";
      description = "systemd MemoryMax hardening directive.";
    };

    cpuQuota = mkOption {
      type = types.str;
      default = "200%";
      description = "systemd CPUQuota hardening directive (200% = 2 cores).";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open apiPort + webhookPort in nixos firewall.";
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      uid = 10000;
      home = cfg.dataDir;
      createHome = false;
      description = "Hermes Agent service user (UID matches migrated Docker volumes)";
    };

    users.groups.${cfg.group} = {
      gid = 10000;
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.apiPort cfg.webhookPort];
    };

    systemd.services.hermes-agent = {
      description = "Hermes Agent (NousResearch) — homelab gateway";
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target" "tailscaled.service"];
      after = ["network-online.target" "tailscaled.service"];

      environment =
        {
          # HERMES_HOME points at mutable storage so lazy deps land outside the nix store.
          HERMES_HOME = cfg.dataDir;
          HERMES_CONFIG_FILE = "${cfg.dataDir}/config.yaml";
          HERMES_SOUL_FILE = "${cfg.dataDir}/SOUL.md";
          HERMES_MAX_ITERATIONS = toString cfg.maxIterations;

          API_SERVER_ENABLED = "true";
          API_SERVER_HOST = cfg.openBindAddress;
          API_SERVER_PORT = toString cfg.apiPort;

          WEBHOOK_ENABLED = "true";
          WEBHOOK_PORT = toString cfg.webhookPort;

          TELEGRAM_ALLOWED_USERS = lib.concatMapStringsSep "," toString cfg.telegramAllowedUsers;

          OPENAI_BASE_URL = cfg.openaiBaseUrl;
        }
        // (lib.optionalAttrs (cfg.apiServerCorsOrigins != []) {
          API_SERVER_CORS_ORIGINS = lib.concatStringsSep "," cfg.apiServerCorsOrigins;
        })
        // (lib.optionalAttrs (cfg.apiServerModelName != "") {
          API_SERVER_MODEL_NAME = cfg.apiServerModelName;
        })
        // (lib.optionalAttrs (cfg.telegramAllowedChats != []) {
          TELEGRAM_ALLOWED_CHATS = lib.concatStringsSep "," cfg.telegramAllowedChats;
        })
        // (lib.optionalAttrs (cfg.telegramAllowedTopics != []) {
          TELEGRAM_ALLOWED_TOPICS = lib.concatStringsSep "," cfg.telegramAllowedTopics;
        })
        // (lib.optionalAttrs cfg.enableDashboard {
          HERMES_DASHBOARD = "1";
          HERMES_DASHBOARD_HOST = cfg.dashboardHost;
          HERMES_DASHBOARD_PORT = toString cfg.dashboardPort;
        })
        // (lib.optionalAttrs (cfg.profile != null) {
          HERMES_PROFILE = cfg.profile;
        });
      # Bridge HERMES_*_BOT_TOKEN -> TELEGRAM_BOT_TOKEN / DISCORD_BOT_TOKEN
      # WEBHOOK_SECRET, OPENAI_API_KEY etc come from EnvironmentFile (sops).
      # Bridge happens inside ExecStart wrapper below since systemd Environment=
      # cannot reference other env vars.

      serviceConfig = {
        Type = "exec";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;

        EnvironmentFile = mkIf (cfg.environmentFile != null) cfg.environmentFile;

        # Bridge HERMES_TELEGRAM_BOT_TOKEN → TELEGRAM_BOT_TOKEN (and same for discord)
        # so the homelab notification stack can keep using TELEGRAM_BOT_TOKEN
        # without collision.
        ExecStart = pkgs.writeShellScript "hermes-exec" ''
          if [ -n "''${HERMES_TELEGRAM_BOT_TOKEN:-}" ]; then
            export TELEGRAM_BOT_TOKEN="$HERMES_TELEGRAM_BOT_TOKEN"
          fi
          if [ -n "''${HERMES_DISCORD_BOT_TOKEN:-}" ]; then
            export DISCORD_BOT_TOKEN="$HERMES_DISCORD_BOT_TOKEN"
          fi
          exec ${cfg.package}/bin/hermes gateway run --replace -v
        '';

        ExecStartPre = "+${bootstrapScript}";

        Restart = "always";
        RestartSec = "10";

        # Hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [cfg.dataDir];
        MemoryMax = cfg.memoryMax;
        CPUQuota = cfg.cpuQuota;

        # Additional defense
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
      };
    };

    # Optional healthcheck timer — curls /health, restarts if down for 3 ticks.
    systemd.services.hermes-agent-healthcheck = {
      description = "Hermes Agent healthcheck";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "hermes-healthcheck" ''
          ${pkgs.curl}/bin/curl -fsS --max-time 5 \
            http://127.0.0.1:${toString cfg.apiPort}/health > /dev/null
        '';
      };
    };

    systemd.timers.hermes-agent-healthcheck = {
      description = "Hermes Agent healthcheck timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "60s";
      };
    };
  };
}
