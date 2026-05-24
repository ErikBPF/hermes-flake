{packages}: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.hermes-agent;
  inherit (lib) mkOption mkEnableOption mkIf types optionalAttrs optionalString;
in {
  options.programs.hermes-agent = {
    enable = mkEnableOption "hermes-agent (NousResearch self-improving AI agent)";

    package = mkOption {
      type = types.package;
      default = packages.${pkgs.system}.hermes-agent.withExtras cfg.extras;
      defaultText = "hermes-flake.packages.\${system}.hermes-agent.withExtras cfg.extras";
      description = ''
        Which hermes-agent build to install. Defaults to a build derived
        from `cfg.extras` via the flake's `withExtras` passthru.
      '';
    };

    extras = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        Upstream hermes-agent extras to include in the user-mode install.
        Same semantics as the NixOS module's `extras`. Discover via:

            nix eval github:ErikBPF/hermes-flake#hermes-agent.availableExtras
      '';
      example = ["voice" "anthropic"];
    };

    configDir = mkOption {
      type = types.str;
      default = "${config.xdg.configHome}/hermes";
      defaultText = "\${XDG_CONFIG_HOME}/hermes";
      description = "Path to hermes config dir. Exported as HERMES_CONFIG_DIR.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "${config.xdg.dataHome}/hermes";
      defaultText = "\${XDG_DATA_HOME}/hermes";
      description = "Path to hermes data dir (memory, skills, history). Exported as HERMES_DATA_DIR.";
    };

    cacheDir = mkOption {
      type = types.str;
      default = "${config.xdg.cacheHome}/hermes";
      defaultText = "\${XDG_CACHE_HOME}/hermes";
      description = "Path to hermes cache dir.";
    };

    secrets = {
      openaiApiKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to file containing OPENAI_API_KEY (e.g. sops-nix rendered secret).
          File is read at shell init via systemd EnvironmentFile-style sourcing.
        '';
        example = "/run/secrets/hermes/openai";
      };

      anthropicApiKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing ANTHROPIC_API_KEY.";
        example = "/run/secrets/hermes/anthropic";
      };

      openrouterApiKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing OPENROUTER_API_KEY.";
      };

      extraKeyFiles = mkOption {
        type = types.attrsOf types.path;
        default = {};
        description = ''
          Map of ENV_VAR_NAME → file path. Each file's contents become the env var value at shell init.
          Use for arbitrary additional API keys / secrets.
        '';
        example = lib.literalExpression ''
          {
            EXA_API_KEY = "/run/secrets/hermes/exa";
            FIRECRAWL_API_KEY = "/run/secrets/hermes/firecrawl";
          }
        '';
      };
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Extra static env vars exported for hermes (non-secret).";
      example = {
        HERMES_LOG_LEVEL = "info";
        HERMES_DEFAULT_MODEL = "claude-opus-4-7";
      };
    };

    systemdService = {
      enable = mkEnableOption "running hermes-agent as a systemd user service";

      extraArgs = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Args appended to `hermes` invocation in the service.";
        example = ["--gateway" "telegram"];
      };
    };
  };

  config = mkIf cfg.enable {
    home.packages = [cfg.package];

    home.sessionVariables =
      {
        HERMES_CONFIG_DIR = cfg.configDir;
        HERMES_DATA_DIR = cfg.dataDir;
        HERMES_CACHE_DIR = cfg.cacheDir;
      }
      // cfg.extraEnvironment;

    # Ensure dirs exist
    home.activation.hermes-dirs = lib.hm.dag.entryAfter ["writeBoundary"] ''
      mkdir -p "${cfg.configDir}" "${cfg.dataDir}" "${cfg.cacheDir}"
    '';

    # Source secrets + extraEnvironment into shell sessions (fish + bash).
    # Secrets: file path → file contents become env var value.
    # Extra env: static key=value pairs exported directly.
    #
    # NOTE: home.sessionVariables alone is unreliable for fish (HM emits a
    # function `setup_hm_session_vars` but doesn't always invoke it).
    # Re-exporting via shellInit guarantees the vars are present on every
    # interactive shell.
    programs.bash.initExtra = let
      secretLine = var: file: ''[ -r "${file}" ] && export ${var}="$(< "${file}")"'';
      envLine = var: value: ''export ${var}="${value}"'';
      lines = lib.flatten [
        (lib.mapAttrsToList envLine cfg.extraEnvironment)
        (lib.optional (cfg.secrets.openaiApiKeyFile != null) (secretLine "OPENAI_API_KEY" cfg.secrets.openaiApiKeyFile))
        (lib.optional (cfg.secrets.anthropicApiKeyFile != null) (secretLine "ANTHROPIC_API_KEY" cfg.secrets.anthropicApiKeyFile))
        (lib.optional (cfg.secrets.openrouterApiKeyFile != null) (secretLine "OPENROUTER_API_KEY" cfg.secrets.openrouterApiKeyFile))
        (lib.mapAttrsToList secretLine cfg.secrets.extraKeyFiles)
      ];
    in
      lib.optionalString (lines != []) (lib.concatStringsSep "\n" lines + "\n");

    programs.fish.shellInit = let
      secretLine = var: file: ''test -r "${file}"; and set -gx ${var} (cat "${file}")'';
      envLine = var: value: ''set -gx ${var} "${value}"'';
      lines = lib.flatten [
        (lib.mapAttrsToList envLine cfg.extraEnvironment)
        (lib.optional (cfg.secrets.openaiApiKeyFile != null) (secretLine "OPENAI_API_KEY" cfg.secrets.openaiApiKeyFile))
        (lib.optional (cfg.secrets.anthropicApiKeyFile != null) (secretLine "ANTHROPIC_API_KEY" cfg.secrets.anthropicApiKeyFile))
        (lib.optional (cfg.secrets.openrouterApiKeyFile != null) (secretLine "OPENROUTER_API_KEY" cfg.secrets.openrouterApiKeyFile))
        (lib.mapAttrsToList secretLine cfg.secrets.extraKeyFiles)
      ];
    in
      lib.optionalString (lines != []) (lib.concatStringsSep "\n" lines + "\n");

    # Optional systemd user service — runs hermes as long-running gateway process.
    systemd.user.services.hermes-agent = mkIf cfg.systemdService.enable {
      Unit = {
        Description = "hermes-agent (NousResearch) gateway";
        After = ["network-online.target"];
        Wants = ["network-online.target"];
      };
      Service = let
        secretEnvFiles = lib.filter (p: p != null) [
          cfg.secrets.openaiApiKeyFile
          cfg.secrets.anthropicApiKeyFile
          cfg.secrets.openrouterApiKeyFile
        ];
      in {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/hermes ${lib.escapeShellArgs cfg.systemdService.extraArgs}";
        Restart = "on-failure";
        RestartSec = "10s";
        Environment = lib.mapAttrsToList (k: v: "${k}=${v}") ({
            HERMES_CONFIG_DIR = cfg.configDir;
            HERMES_DATA_DIR = cfg.dataDir;
            HERMES_CACHE_DIR = cfg.cacheDir;
          }
          // cfg.extraEnvironment);
      };
      Install.WantedBy = ["default.target"];
    };
  };
}
