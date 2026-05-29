{
  description = "Third-party Nix flake for NousResearch/hermes-agent — NixOS service module + container/microvm/podman wrappers + per-user home-manager module";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hermes-agent-src = {
      url = "github:NousResearch/hermes-agent/v2026.5.29.2";
      flake = false;
    };

    # Optional — only required when using nixosModules.hermes-agent-microvm.
    # Pull only when the consumer wires it; nothing forces it as a runtime dep.
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];

      perSystem = {
        pkgs,
        system,
        lib,
        ...
      }: let
        pkgsUnfree = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        hermesPackages = import ./package.nix {
          pkgs = pkgsUnfree;
          inherit lib inputs system;
        };
      in {
        _module.args.pkgs = pkgsUnfree;

        packages = {
          default = hermesPackages.hermes-agent;
          inherit (hermesPackages) hermes-agent hermes-agent-full;
        };

        apps = {
          default = {
            type = "app";
            program = "${hermesPackages.hermes-agent}/bin/hermes";
            meta.description = "Run hermes CLI";
          };
          hermes-acp = {
            type = "app";
            program = "${hermesPackages.hermes-agent}/bin/hermes-acp";
            meta.description = "Run hermes-acp adapter";
          };
          hermes-agent = {
            type = "app";
            program = "${hermesPackages.hermes-agent}/bin/hermes-agent";
            meta.description = "Run hermes-agent runner";
          };

          # nix run .#update — apply latest upstream release
          update = {
            type = "app";
            program = toString (pkgs.writeShellScript "hermes-flake-update" ''
              set -euo pipefail
              cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel 2>/dev/null \
                    || { echo "must be run from inside the flake repo" >&2; exit 1; })"
              exec ${pkgs.bash}/bin/bash ./scripts/update-version.sh "$@"
            '');
            meta.description = "Check + apply the latest upstream hermes-agent release";
          };

          # nix run .#update-check — exit 1 if upstream has a newer release
          update-check = {
            type = "app";
            program = toString (pkgs.writeShellScript "hermes-flake-update-check" ''
              set -euo pipefail
              cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel 2>/dev/null \
                    || { echo "must be run from inside the flake repo" >&2; exit 1; })"
              exec ${pkgs.bash}/bin/bash ./scripts/update-version.sh --check
            '');
            meta.description = "Exit 1 if an upstream hermes-agent release is newer than the pin";
          };
        };

        checks = import ./checks.nix {
          inherit pkgs lib self system;
        };

        formatter = pkgs.alejandra;

        devShells.default = pkgs.mkShellNoCC {
          name = "hermes-flake-dev";
          packages = with pkgs; [
            # nix + lint
            nix
            alejandra
            statix
            deadnix
            nil # nix LSP
            # update flow
            curl
            jq
            git
            # task runner
            just
            # for the update script
            gnused
            findutils
          ];
          shellHook = ''
            echo "hermes-flake dev shell"
            echo "  just --list        show recipes"
            echo "  just check         run nix flake check"
            echo "  just update-check  see if upstream has a newer hermes-agent"
          '';
        };
      };

      flake = {
        nixosModules.default = {
          config,
          lib,
          pkgs,
          ...
        }:
          import ./module.nix {
            inherit config lib pkgs;
            flakePackages = self.packages;
          };

        nixosModules.hermes-agent = self.nixosModules.default;

        nixosModules.hermes-agent-container = {
          config,
          lib,
          pkgs,
          ...
        }:
          import ./container.nix {
            inherit config lib pkgs;
            flakeSelf = self;
          };

        nixosModules.hermes-agent-microvm = {
          config,
          lib,
          pkgs,
          ...
        }:
          import ./microvm.nix {
            inherit config lib pkgs;
            flakeInputs = inputs;
            flakeSelf = self;
          };

        nixosModules.hermes-agent-podman = {
          config,
          lib,
          pkgs,
          ...
        }:
          import ./podman.nix {
            inherit config lib pkgs;
            flakeSelf = self;
          };

        homeManagerModules.default = import ./modules/home-manager.nix {
          inherit (self) packages;
        };

        homeManagerModules.hermes-agent = self.homeManagerModules.default;

        # Overlay — `pkgs.hermes-agent` (with .withExtras passthru) for
        # downstream consumers.
        overlays.default = final: prev: {
          inherit (self.packages.${prev.system}) hermes-agent hermes-agent-full;
        };

        # Template — `nix flake new -t github:ErikBPF/hermes-flake my-config`
        # scaffolds a minimal NixOS host wired to this flake + sops-nix.
        templates.default = {
          path = ./templates/default;
          description = "Minimal NixOS host with hermes-agent + sops-nix";
          welcomeText = ''
            hermes-flake template scaffolded. Next steps:

            1. Replace fileSystems / hardware-configuration with your real host's.
            2. Encrypt your env file:    sops secrets/hermes.env.sops
            3. Build:                    nix build .#nixosConfigurations.myhost.config.system.build.toplevel
            4. Deploy:                   nixos-rebuild switch --flake .#myhost --target-host myhost

            Docs:
              - https://github.com/ErikBPF/hermes-flake/blob/main/docs/SOPS.md
              - https://github.com/ErikBPF/hermes-flake/blob/main/docs/ENV_VARS.md
          '';
        };

        templates.minimal = self.templates.default;
      };
    };
}
