{
  config,
  lib,
  pkgs,
  flakeSelf,
  ...
}: let
  cfg = config.services.hermes-agent-container;
  inherit (lib) mkOption mkEnableOption mkIf types;
  shared = import ./nixos/wrapper-options.nix {inherit lib pkgs;};
in {
  options.services.hermes-agent-container =
    shared.options
    // {
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
          the container.
        '';
      };

      privateNetwork = mkOption {
        type = types.bool;
        default = false;
        description = ''
          false (default): container shares host network. Port 8642/8644 bind
          host directly. Simpler, SWAG works as-is.

          true: container gets its own veth. Stronger isolation. Requires
          `forwardPorts` to expose ports.
        '';
      };

      forwardPorts = mkOption {
        type = types.listOf types.attrs;
        default = [];
        description = ''
          Only used when privateNetwork = true. Forwards host ports into the
          container. Defaults to apiPort + webhookPort if empty.
        '';
      };

      autoStart = mkOption {
        type = types.bool;
        default = true;
      };

      stateVersion = mkOption {
        type = types.str;
        default = "26.05";
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
        "/var/lib/hermes-agent" = {
          hostPath = toString cfg.hostDataDir;
          isReadOnly = false;
        };
        "${toString cfg.hostSecretsPath}" = {
          hostPath = toString cfg.hostSecretsPath;
          isReadOnly = true;
        };
      };

      config = {...}: {
        imports = [flakeSelf.nixosModules.default];

        services.hermes-agent =
          (shared.toInner cfg)
          // {
            environmentFile = cfg.hostSecretsPath;
            openFirewall = cfg.privateNetwork;
          };

        system.stateVersion = cfg.stateVersion;
        networking.firewall.allowedTCPPorts =
          lib.optionals cfg.privateNetwork [cfg.apiPort cfg.webhookPort];
      };
    };
  };
}
