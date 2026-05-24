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
    enable = mkEnableOption "Hermes Agent (NousResearch) — autonomous AI agent system service";

    package = mkOption {
      type = types.package;
      default = flakePackages.${pkgs.system}.hermes-agent.withExtras cfg.extras;
      defaultText = "hermes-flake.packages.\${system}.hermes-agent.withExtras cfg.extras";
      description = ''
        Hermes-agent package to run. By default, derived from
        `cfg.extras` via the flake's `withExtras` passthru. Set explicitly
        to override (e.g. to use the prebuilt `hermes-agent-full`).
      '';
    };

    extras = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        Upstream hermes-agent extras to include. The package is rebuilt
        with the listed optional dep groups. Unknown extra names error
        at eval time. Inspect available names via:

            nix eval .#hermes-agent.availableExtras

        Common picks:
        - `voice`        — STT (faster-whisper) + audio (sounddevice)
        - `anthropic`    — direct Anthropic SDK
        - `mcp`          — Model Context Protocol support
        - `web`          — FastAPI + uvicorn
        - `bedrock`      — AWS Bedrock provider
        - `exa` / `firecrawl` / `parallel-web` / `tavily` — search backends

        Some extras (dingtalk, feishu, matrix) pull sdist-only packages
        that may need additions to `overrides.nix` before they build.
      '';
      example = ["voice" "anthropic" "mcp"];
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
        Merges recursively with the bundled default in config.yaml.nix.
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
        Path to a SOUL.md personality file. Defaults to the bundled
        placeholder; override with your own persona file.
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
      example = [123456789];
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
      default = "https://api.openai.com/v1";
      description = ''
        OPENAI_BASE_URL — set to your provider (OpenAI, OpenRouter, LiteLLM
        proxy, local llama-server, etc.).
      '';
      example = "https://openrouter.ai/api/v1";
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

    extraServiceDeps = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        Extra systemd units to add to `Wants=` and `After=`. Useful for
        environments where hermes must wait for site-specific services like
        `tailscaled.service` before starting.
      '';
      example = ["tailscaled.service" "sops-nix.service"];
    };

    enableHealthcheck = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Run a one-shot health check service every 60s that curls
        `/health` on the API server. Disable if you already poll the
        endpoint from an external monitoring stack.
      '';
    };

    healthcheckInterval = mkOption {
      type = types.str;
      default = "60s";
      description = "systemd `OnUnitActiveSec` for the healthcheck timer.";
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
      description = "Hermes Agent (NousResearch) — gateway service";
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"] ++ cfg.extraServiceDeps;
      after = ["network-online.target"] ++ cfg.extraServiceDeps;

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

        # Bridge HERMES_TELEGRAM_BOT_TOKEN → TELEGRAM_BOT_TOKEN (and same for
        # discord) so the same env file can be shared with a separate
        # notification stack that already claims the bare names.
        ExecStart = pkgs.writeShellScript "hermes-exec" ''
          # Bridge prefixed secrets to upstream-expected names so the same env
          # file can be shared with other services (notification stacks etc.)
          # that already claim the bare TELEGRAM_BOT_TOKEN name.
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

    # Optional healthcheck — curls /health every cfg.healthcheckInterval.
    systemd.services.hermes-agent-healthcheck = mkIf cfg.enableHealthcheck {
      description = "Hermes Agent healthcheck";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "hermes-healthcheck" ''
          ${pkgs.curl}/bin/curl -fsS --max-time 5 \
            http://127.0.0.1:${toString cfg.apiPort}/health > /dev/null
        '';
      };
    };

    systemd.timers.hermes-agent-healthcheck = mkIf cfg.enableHealthcheck {
      description = "Hermes Agent healthcheck timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = cfg.healthcheckInterval;
      };
    };
  };
}
