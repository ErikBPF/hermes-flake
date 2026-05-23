{
  config,
  lib,
  pkgs,
  flakeInputs,
  flakeSelf,
  ...
}: let
  cfg = config.services.hermes-agent-microvm;
  inherit (lib) mkOption mkEnableOption mkIf mkRemovedOptionModule types;
  shared = import ./nixos/wrapper-options.nix {inherit lib pkgs;};
in {
  imports = [
    (mkRemovedOptionModule
      ["services" "hermes-agent-microvm" "extraServiceOptions"]
      "Removed; every inner option now has a first-class wrapper option. See container.nix's removal notice for the migration pattern.")
  ];

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
          host's bridge config and `interfaces` below.
        '';
      };

      interfaces = mkOption {
        type = types.listOf types.attrs;
        default = [];
        description = ''
          microvm.interfaces passed verbatim to the guest. For qemu, leave
          empty — a user-net interface is auto-generated. For firecracker /
          cloud-hypervisor / crosvm / kvmtool, the consumer MUST supply at
          least one interface (typically TAP+bridge); otherwise the guest
          boots without networking and the API server is unreachable.
        '';
        example = lib.literalExpression ''
          [{ type = "tap"; id = "vm-hermes"; mac = "02:00:00:01:01:01"; }]
        '';
      };

      openFirewallInGuest = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to open apiPort + webhookPort in the GUEST's NixOS
          firewall. Disable when you want host-side packet filtering to be
          the sole gate (e.g. with a bridge + nftables policy on the host).
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

          # qemu gets an auto user-net interface; other hypervisors must
          # be supplied via cfg.interfaces. If the consumer supplied their
          # own, use those even on qemu (TAP/bridge etc.).
          interfaces =
            if cfg.interfaces != []
            then cfg.interfaces
            else if cfg.hypervisor == "qemu"
            then [
              {
                type = "user";
                id = "vm-${cfg.vmName}";
                mac = "02:00:00:01:01:01";
              }
            ]
            else
              throw ''
                services.hermes-agent-microvm.hypervisor = "${cfg.hypervisor}"
                requires services.hermes-agent-microvm.interfaces to be set
                (only qemu user-net is auto-generated).
              '';

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

        networking.firewall.allowedTCPPorts =
          lib.optionals cfg.openFirewallInGuest [cfg.apiPort cfg.webhookPort];
        networking.hostName = cfg.vmName;

        services.hermes-agent =
          (shared.toInner cfg)
          // {
            environmentFile = cfg.hostSecretsPath;
            # Honour the consumer's openBindAddress. Default is `127.0.0.1`
            # from wrapper-options — which means the VM's services are only
            # reachable inside the VM. To expose them via qemu user-net
            # forwarding (or a bridge), set:
            #   services.hermes-agent-microvm.openBindAddress = "0.0.0.0";
            # The base-module assertion will then require environmentFile,
            # already set above.
            openFirewall = cfg.openFirewallInGuest;
          };

        system.stateVersion = cfg.stateVersion;
      };
    };
  };
}
