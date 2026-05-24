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
  shared = import ./nixos/wrapper-options.nix {inherit lib pkgs;};
in {
  options.services.hermes-agent-microvm =
    shared.options
    // {
      enable = mkEnableOption "Run hermes-agent inside a microvm (KVM-isolated)";

      vmName = mkOption {
        type = types.str;
        default = "hermes";
      };

      hostDataDir = mkOption {
        type = types.path;
        default = "/var/lib/hermes-agent";
      };

      hostSecretsPath = mkOption {
        type = types.str;
        default = "/run/secrets/hermes-agent/env";
        description = ''
          Host path to the sops-decrypted env FILE. Must point at a specific
          file (not a directory) — the virtiofs share scopes to the file's
          parent directory, so place the env file in a dedicated subdir
          (e.g. /run/secrets/hermes-agent/env) to avoid leaking sibling
          secrets into the guest. Asserted at build time.

          Type is `str` (not `path`) to prevent Nix from copying the runtime
          file into the store at eval time.
        '';
      };

      memMB = mkOption {
        type = types.int;
        default = 2048;
      };

      vcpu = mkOption {
        type = types.int;
        default = 2;
      };

      hypervisor = mkOption {
        type = types.enum ["qemu" "cloud-hypervisor" "firecracker" "crosvm" "kvmtool"];
        default = "qemu";
      };

      forwardPorts = mkOption {
        type = types.listOf types.attrs;
        default = [];
        description = ''
          Only used with `hypervisor = "qemu"` (user-net forwards). Other
          hypervisors require TAP+bridge networking — wire ports via the
          host's bridge config instead.
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
      {
        # Refuse the default `/run/secrets` parent dir — sharing the whole
        # /run/secrets/ tree into the VM is a foot-gun. Require an explicit
        # subdir.
        assertion = !(builtins.elem (builtins.dirOf cfg.hostSecretsPath) ["/run/secrets" "/var/lib/secrets" "/etc/secrets"]);
        message = ''
          services.hermes-agent-microvm.hostSecretsPath = "${cfg.hostSecretsPath}"
          would share the parent directory "${builtins.dirOf cfg.hostSecretsPath}"
          into the guest — that directory typically holds OTHER services'
          decrypted secrets and would be exposed to anything running in the
          microvm.

          Place the hermes env file in a dedicated subdirectory, e.g.

              sops.secrets."hermes-agent/env" = {
                ...
                path = "/run/secrets/hermes-agent/env";
              };
              services.hermes-agent-microvm.hostSecretsPath =
                "/run/secrets/hermes-agent/env";
        '';
      }
    ];

    microvm.vms.${cfg.vmName} = {
      autostart = cfg.autoStart;
      config = {...}: {
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
            {
              # Mount the parent of the secret file (virtiofs can't share a
              # single file). The assertion above enforces this parent is a
              # dedicated subdir, not a shared secrets root.
              tag = "hermes-secrets";
              source = builtins.dirOf cfg.hostSecretsPath;
              mountPoint = builtins.dirOf cfg.hostSecretsPath;
              proto = "virtiofs";
            }
          ];

          interfaces = lib.mkIf (cfg.hypervisor == "qemu") [
            {
              type = "user";
              id = "vm-${cfg.vmName}";
              mac = "02:00:00:01:01:01";
            }
          ];

          # forwardPorts is qemu-user-net specific. Skip for other hypervisors.
          forwardPorts = mkIf (cfg.hypervisor == "qemu") (
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
            else cfg.forwardPorts
          );
        };

        networking.firewall.allowedTCPPorts = [cfg.apiPort cfg.webhookPort];
        networking.hostName = cfg.vmName;

        services.hermes-agent =
          (shared.toInner cfg)
          // {
            environmentFile = cfg.hostSecretsPath;
            openBindAddress = "0.0.0.0"; # inside the VM, bind every NIC
            openFirewall = true;
          };

        system.stateVersion = cfg.stateVersion;
      };
    };
  };
}
