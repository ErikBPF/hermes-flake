{
  description = "Nix flake packaging NousResearch/hermes-agent with NixOS service module";

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
      url = "github:NousResearch/hermes-agent/v2026.5.16";
      flake = false;
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
          inherit
            (hermesPackages)
            hermes-agent
            hermes-agent-voice
            hermes-agent-messaging
            hermes-agent-web
            hermes-agent-mcp
            hermes-agent-bedrock
            hermes-agent-full
            ;
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
        };

        checks = import ./checks.nix {
          inherit pkgs lib self system;
        };

        formatter = pkgs.alejandra;
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

        homeManagerModules.default = import ./modules/home-manager.nix {
          inherit (self) packages;
        };

        homeManagerModules.hermes-agent = self.homeManagerModules.default;

        # Overlay — `pkgs.hermes-agent` (and variants) for downstream consumers.
        overlays.default = final: prev: {
          inherit
            (self.packages.${prev.system})
            hermes-agent
            hermes-agent-voice
            hermes-agent-messaging
            hermes-agent-web
            hermes-agent-mcp
            hermes-agent-bedrock
            hermes-agent-full
            ;
        };
      };
    };
}
