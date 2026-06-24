# Run the OFFICIAL upstream hermes-agent Docker image via
# virtualisation.oci-containers — the upstream-adherent production path.
#
# Unlike module.nix / container.nix / podman.nix (which run a uv2nix-rebuilt
# package, or a dockerTools image built from it), this module pulls the image
# NousResearch publishes and tests: `nousresearch/hermes-agent`. You get the
# upstream s6 supervision tree, the tested dependency set, and `docker pull`
# upgrades — with Nix layering the declarative wrapper on top: rendered
# config.yaml + SOUL.md, sops env, /opt/data persistence, pinned tag.
#
# Trade-off vs the package-based modules: `package` and `extras` are NO-OPS
# here (the image ships its own deps). Use services.hermes-agent (bare-metal)
# or services.hermes-agent-podman (nix-built image) when you want a
# from-source closure instead of the vendor image.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hermes-agent-oci;
  inherit (lib) mkOption mkEnableOption mkIf types;
  shared = import ./wrapper-options.nix {inherit lib pkgs;};

  # Render config.yaml from `settings` (merges over config.yaml.nix defaults),
  # unless the consumer pins an explicit file.
  renderedConfig =
    if cfg.configFile != null
    then cfg.configFile
    else
      import ../config.yaml.nix {
        inherit pkgs lib;
        settings = cfg.settings;
      };

  soulFile =
    if cfg.soulFile != null
    then cfg.soulFile
    else ../SOUL.md;
in {
  options.services.hermes-agent-oci =
    shared.options
    // {
      enable = mkEnableOption "Run the official upstream hermes-agent Docker image via virtualisation.oci-containers";

      image = mkOption {
        type = types.str;
        default = "nousresearch/hermes-agent:latest";
        description = ''
          Official upstream image reference (Docker Hub). PIN a tag or digest
          for production, e.g.
            "nousresearch/hermes-agent@sha256:<digest>"
          A digest is the only fully reproducible form. NOTE: under
          oci-containers, a moving `:latest` is NOT re-pulled on every
          activation the way compose `pull_policy: always` is — the backend
          pulls only when the reference is absent locally. Pin something you
          bump deliberately.
        '';
        example = "nousresearch/hermes-agent@sha256:abc123";
      };

      backend = mkOption {
        type = types.enum ["podman" "docker"];
        default = "docker";
        description = "Container runtime backend. Applied via mkDefault so coexisting OCI modules don't conflict.";
      };

      containerName = mkOption {
        type = types.str;
        default = "hermes-agent";
      };

      hostDataDir = mkOption {
        type = types.path;
        default = "/var/lib/hermes-agent";
        description = ''
          Host directory bound into the container at /opt/data — upstream's
          hardcoded HERMES_HOME. Holds ALL mutable state: sessions, memories,
          skills, lazy-installed venv. SHOULD be a btrfs subvolume for
          snapshots. The rendered config.yaml + SOUL.md are overlaid on top as
          read-only file mounts.
        '';
      };

      environmentFile = mkOption {
        type = types.path;
        description = ''
          sops-decrypted dotenv carrying secrets under upstream-BARE names
          (no HERMES_ bridge on this path): OPENAI_API_KEY, API_SERVER_KEY
          (mandatory when bound beyond loopback), TELEGRAM_BOT_TOKEN,
          DISCORD_BOT_TOKEN, EXA_API_KEY, ...
        '';
        example = "/run/secrets/hermes-agent";
      };

      cmd = mkOption {
        type = types.listOf types.str;
        default = ["gateway" "run" "--replace" "-v"];
        description = "Container command. Upstream's persistent-gateway invocation.";
      };

      autoStart = mkOption {
        type = types.bool;
        default = true;
      };
    };

  config = mkIf cfg.enable {
    assertions = [
      {
        # Binding non-loopback without a secret-carrying env file leaves the
        # API server unauthenticated — API_SERVER_KEY MUST be present.
        assertion = (shared.isLoopback cfg.openBindAddress) || cfg.environmentFile != null;
        message = ''
          services.hermes-agent-oci.openBindAddress = "${cfg.openBindAddress}"
          exposes the API server beyond loopback. Set environmentFile to a
          sops dotenv carrying at least API_SERVER_KEY.
        '';
      }
    ];

    virtualisation.oci-containers.backend = lib.mkDefault cfg.backend;

    virtualisation.oci-containers.containers.${cfg.containerName} = {
      inherit (cfg) image autoStart cmd;

      # HERMES_HOME is hardcoded to /opt/data in the upstream entrypoint; set
      # it explicitly for clarity (informational — the entrypoint wins anyway).
      environment =
        {
          HERMES_HOME = "/opt/data";
          API_SERVER_ENABLED = "true";
          API_SERVER_HOST = cfg.openBindAddress;
          API_SERVER_PORT = toString cfg.apiPort;
          WEBHOOK_ENABLED = "true";
          WEBHOOK_PORT = toString cfg.webhookPort;
          OPENAI_BASE_URL = cfg.openaiBaseUrl;
          HERMES_MAX_ITERATIONS = toString cfg.maxIterations;
        }
        // (lib.optionalAttrs (cfg.telegramAllowedUsers != []) {
          TELEGRAM_ALLOWED_USERS = lib.concatMapStringsSep "," toString cfg.telegramAllowedUsers;
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
        // (lib.optionalAttrs (cfg.profile != null) {
          HERMES_PROFILE = cfg.profile;
        })
        // (lib.optionalAttrs cfg.enableDashboard {
          HERMES_DASHBOARD = "1";
          HERMES_DASHBOARD_HOST = cfg.dashboardHost;
          HERMES_DASHBOARD_PORT = toString cfg.dashboardPort;
        })
        // cfg.extraEnvironment;

      environmentFiles = [cfg.environmentFile];

      ports =
        [
          "${cfg.openBindAddress}:${toString cfg.apiPort}:${toString cfg.apiPort}"
          "${cfg.openBindAddress}:${toString cfg.webhookPort}:${toString cfg.webhookPort}"
        ]
        ++ lib.optional cfg.enableDashboard
        "${cfg.dashboardHost}:${toString cfg.dashboardPort}:${toString cfg.dashboardPort}";

      # Mutable state dir + read-only overlay of the rendered config & soul,
      # mirroring the upstream/servarr layout exactly.
      volumes = [
        "${toString cfg.hostDataDir}:/opt/data"
        "${renderedConfig}:/opt/data/config.yaml:ro"
        "${soulFile}:/opt/data/SOUL.md:ro"
      ];

      extraOptions = lib.optional (cfg.memoryMax != null) "--memory=${cfg.memoryMax}";
    };

    # /opt/data is owned by UID/GID 10000 inside the image (entrypoint drops to
    # it via gosu). Pre-create the host dir with the matching owner.
    systemd.tmpfiles.rules = [
      "d ${toString cfg.hostDataDir} 0750 10000 10000 -"
    ];
  };
}
