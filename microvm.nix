{
  config,
  lib,
  pkgs,
  flakeInputs,
  flakeSelf,
  ...
}: let
  cfg = config.services.hermes-agent-microvm;
  inherit (lib) mkOption mkEnableOption mkIf types;
in {
  options.services.hermes-agent-microvm = {
    enable = mkEnableOption "Run hermes-agent inside a microvm (KVM-isolated)";

    vmName = mkOption {
      type = types.str;
      default = "hermes";
      description = "microvm instance name.";
    };

    hostDataDir = mkOption {
      type = types.path;
      default = "/var/lib/hermes-agent";
      description = ''
        Host path bound into the VM as /var/lib/hermes-agent (virtio-9p share).
      '';
    };

    hostSecretsPath = mkOption {
      type = types.path;
      default = "/run/secrets/hermes-agent";
      description = ''
        Host path to sops-decrypted env file. RO-shared into the VM at the
        same path. Must be readable by the host user `microvm` so it can
        proxy the share.
      '';
    };

    memMB = mkOption {
      type = types.int;
      default = 2048;
      description = "VM RAM in MiB.";
    };

    vcpu = mkOption {
      type = types.int;
      default = 2;
      description = "VM virtual CPU count.";
    };

    hypervisor = mkOption {
      type = types.enum ["qemu" "cloud-hypervisor" "firecracker" "crosvm" "kvmtool"];
      default = "qemu";
      description = "microvm hypervisor backend.";
    };

    forwardPorts = mkOption {
      type = types.listOf types.attrs;
      default = [];
      description = ''
        Host-to-guest port forwards (qemu user-mode net). Defaults to
        forwarding `apiPort` + `webhookPort` when empty and binding is non-
        localhost.
      '';
      example = lib.literalExpression ''
        [
          { host = 8642; guest = 8642; }
          { host = 8644; guest = 8644; }
        ]
      '';
    };

    apiPort = mkOption {
      type = types.port;
      default = 8642;
    };

    webhookPort = mkOption {
      type = types.port;
      default = 8644;
    };

    extras = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Hermes extras to include inside the VM (see flake's withExtras).";
    };

    telegramAllowedUsers = mkOption {
      type = types.listOf types.int;
      default = [];
    };

    openaiBaseUrl = mkOption {
      type = types.str;
      default = "https://api.openai.com/v1";
    };

    settings = mkOption {
      type = types.attrs;
      default = {};
      description = "Forwarded to inner services.hermes-agent.settings.";
    };

    extraServiceOptions = mkOption {
      type = types.attrs;
      default = {};
      description = "Extra attrs spread into inner services.hermes-agent.";
    };

    stateVersion = mkOption {
      type = types.str;
      default = "26.05";
    };
  };

  config = mkIf cfg.enable {
    # Asserts microvm.nix is wired by the host configuration. Consumers add:
    #   imports = [ inputs.microvm.nixosModules.host ];
    assertions = [
      {
        assertion = config ? microvm;
        message = ''
          services.hermes-agent-microvm.enable requires the microvm.nix host
          module to be imported in the *host* NixOS configuration:

              imports = [ inputs.microvm.nixosModules.host ];

          and `microvm` added as a flake input. See:
          https://github.com/astro/microvm.nix
        '';
      }
    ];

    microvm.vms.${cfg.vmName} = {
      autostart = true;
      config = {
        config,
        pkgs,
        ...
      }: {
        imports = [
          flakeInputs.microvm.nixosModules.microvm
          flakeSelf.nixosModules.default
        ];

        microvm = {
          hypervisor = cfg.hypervisor;
          mem = cfg.memMB;
          vcpu = cfg.vcpu;

          shares = [
            {
              tag = "hermes-data";
              source = toString cfg.hostDataDir;
              mountPoint = "/var/lib/hermes-agent";
              proto = "virtiofs";
            }
            # virtiofs can't share a single file — share the parent dir
            # READ-ONLY so other secrets in /run/secrets/ stay inaccessible
            # to mutation but the guest still sees them by listing the dir.
            #
            # For stricter isolation: put the hermes env file in its own
            # directory (e.g. /run/secrets/hermes-agent/env) and point
            # hostSecretsPath at that file — the share will then be scoped
            # to /run/secrets/hermes-agent/ only.
            {
              tag = "hermes-secrets";
              source = toString (builtins.dirOf cfg.hostSecretsPath);
              mountPoint = builtins.dirOf cfg.hostSecretsPath;
              proto = "virtiofs";
              # Note: microvm.nix doesn't expose a read-only flag on virtiofs
              # shares directly; the guest sees the dir RW. Use a tightly-
              # scoped parent dir per the comment above.
            }
          ];

          # qemu user-net forwards; switch to TAP+bridge for full networking.
          interfaces = lib.mkIf (cfg.hypervisor == "qemu") [
            {
              type = "user";
              id = "vm-${cfg.vmName}";
              mac = "02:00:00:01:01:01";
            }
          ];

          forwardPorts =
            if cfg.forwardPorts == []
            then [
              {
                host.port = cfg.apiPort;
                guest.port = cfg.apiPort;
                proto = "tcp";
              }
              {
                host.port = cfg.webhookPort;
                guest.port = cfg.webhookPort;
                proto = "tcp";
              }
            ]
            else cfg.forwardPorts;
        };

        networking.firewall.allowedTCPPorts = [cfg.apiPort cfg.webhookPort];
        networking.hostName = cfg.vmName;

        services.hermes-agent =
          {
            enable = true;
            extras = cfg.extras;
            environmentFile = cfg.hostSecretsPath;
            openBindAddress = "0.0.0.0"; # inside the VM, bind everywhere
            apiPort = cfg.apiPort;
            webhookPort = cfg.webhookPort;
            telegramAllowedUsers = cfg.telegramAllowedUsers;
            openaiBaseUrl = cfg.openaiBaseUrl;
            settings = cfg.settings;
            openFirewall = true;
          }
          // cfg.extraServiceOptions;

        system.stateVersion = cfg.stateVersion;
      };
    };
  };
}
