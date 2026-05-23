{
  config,
  lib,
  pkgs,
  flakeSelf,
  ...
}: let
  cfg = config.services.hermes-agent-container;
  inherit (lib) mkOption mkEnableOption mkIf types;
in {
  options.services.hermes-agent-container = {
    enable = mkEnableOption "Run hermes-agent inside a nixos-container (systemd-nspawn)";

    containerName = mkOption {
      type = types.str;
      default = "hermes";
      description = "Name of the nspawn container.";
    };

    hostDataDir = mkOption {
      type = types.path;
      default = "/var/lib/hermes-agent";
      description = "Host path bound into the container as /var/lib/hermes-agent.";
    };

    hostSecretsPath = mkOption {
      type = types.path;
      default = "/run/secrets/hermes-agent";
      description = ''
        Host path to sops-decrypted env file. Read-only-bind-mounted into the
        container at the same path. Must be readable by UID 10000 from inside
        the container (file mode 0440 + group hermes works).
      '';
    };

    privateNetwork = mkOption {
      type = types.bool;
      default = false;
      description = ''
        false (default): container shares host network. Port 8642/8644 bind
        host directly — like docker --network=host. Simpler, SWAG works as-is.

        true: container gets its own veth. Stronger isolation. Requires
        `forwardPorts` to expose ports — SWAG conf must point at the
        container's IP via natural host-side port forward.
      '';
    };

    forwardPorts = mkOption {
      type = types.listOf types.attrs;
      default = [];
      description = ''
        Only used when privateNetwork = true. Forwards host ports into the
        container. Defaults to apiPort + webhookPort below if empty.
      '';
      example = lib.literalExpression ''
        [
          { containerPort = 8642; hostPort = 8642; protocol = "tcp"; }
          { containerPort = 8644; hostPort = 8644; protocol = "tcp"; }
        ]
      '';
    };

    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = "Start the container on boot.";
    };

    stateVersion = mkOption {
      type = types.str;
      default = "26.05";
      description = "NixOS stateVersion for the inner container config.";
    };

    settings = mkOption {
      type = types.attrs;
      default = {};
      description = "Forwarded to inner services.hermes-agent.settings.";
    };

    apiPort = mkOption {
      type = types.port;
      default = 8642;
    };

    webhookPort = mkOption {
      type = types.port;
      default = 8644;
    };

    telegramAllowedUsers = mkOption {
      type = types.listOf types.int;
      default = [];
    };

    openaiBaseUrl = mkOption {
      type = types.str;
      default = "https://api.openai.com/v1";
    };

    extraServiceOptions = mkOption {
      type = types.attrs;
      default = {};
      description = "Extra attrs spread into inner services.hermes-agent.";
    };
  };

  config = mkIf cfg.enable {
    containers.${cfg.containerName} = {
      autoStart = cfg.autoStart;
      privateNetwork = cfg.privateNetwork;

      forwardPorts =
        if cfg.privateNetwork && cfg.forwardPorts == []
        then [
          {
            containerPort = cfg.apiPort;
            hostPort = cfg.apiPort;
            protocol = "tcp";
          }
          {
            containerPort = cfg.webhookPort;
            hostPort = cfg.webhookPort;
            protocol = "tcp";
          }
        ]
        else cfg.forwardPorts;

      bindMounts = {
        # State dir — persistent, RW.
        "/var/lib/hermes-agent" = {
          hostPath = toString cfg.hostDataDir;
          isReadOnly = false;
        };

        # sops-decrypted env — RO.
        "${toString cfg.hostSecretsPath}" = {
          hostPath = toString cfg.hostSecretsPath;
          isReadOnly = true;
        };
      };

      config = {
        config,
        pkgs,
        ...
      }: {
        imports = [flakeSelf.nixosModules.default];

        services.hermes-agent =
          {
            enable = true;
            environmentFile = cfg.hostSecretsPath;
            apiPort = cfg.apiPort;
            webhookPort = cfg.webhookPort;
            telegramAllowedUsers = cfg.telegramAllowedUsers;
            openaiBaseUrl = cfg.openaiBaseUrl;
            settings = cfg.settings;
            # Inside the container, openFirewall=true if privateNetwork; the
            # host firewall stays untouched (forwardPorts handles that).
            openFirewall = cfg.privateNetwork;
          }
          // cfg.extraServiceOptions;

        # Minimal inner system — no display, no audio.
        system.stateVersion = cfg.stateVersion;
        networking.firewall.allowedTCPPorts = lib.optional cfg.privateNetwork cfg.apiPort
          ++ lib.optional cfg.privateNetwork cfg.webhookPort;
        # Allow outbound DNS/HTTPS for hermes to reach LiteLLM, Anthropic, etc.
      };
    };
  };
}
