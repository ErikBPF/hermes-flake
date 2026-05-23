{
  description = "hermes-agent on NixOS — bootstrapped from hermes-flake template";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    hermes-flake = {
      url = "github:ErikBPF/hermes-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    hermes-flake,
    sops-nix,
    ...
  }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        sops-nix.nixosModules.sops
        hermes-flake.nixosModules.default

        ({config, ...}: {
          networking.hostName = "myhost";

          # Provide secrets via sops-nix. Encrypt secrets/hermes.env with sops
          # before first activation; see hermes-flake/docs/SOPS.md for the recipe.
          sops.secrets."hermes-agent/env" = {
            sopsFile = ./secrets/hermes.env.sops;
            format = "dotenv";
            owner = "hermes";
            mode = "0440";
          };

          services.hermes-agent = {
            enable = true;
            environmentFile = config.sops.secrets."hermes-agent/env".path;
            extras = ["voice" "anthropic" "mcp"];
            telegramAllowedUsers = [123456789];
            # openBindAddress stays at the default 127.0.0.1.
            # Set to 0.0.0.0 only if reverse-proxying externally — the
            # assertion requires API_SERVER_KEY in environmentFile then.
          };

          # Boilerplate — replace with your hardware-configuration etc.
          fileSystems."/" = {
            device = "/dev/disk/by-label/nixos";
            fsType = "ext4";
          };
          boot.loader.systemd-boot.enable = true;
          system.stateVersion = "26.05";
        })
      ];
    };
  };
}
