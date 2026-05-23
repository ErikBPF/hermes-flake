{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.hermes-flake.nixosModules.default
    inputs.sops-nix.nixosModules.sops
  ];

  # sops setup
  sops = {
    defaultSopsFile = ./secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets."hermes-agent/env" = {
      format = "dotenv";
      sopsFile = ./secrets-hermes.env.sops;
      owner = "hermes";
      mode = "0400";
      path = "/run/secrets/hermes-agent";
    };
  };

  services.hermes-agent = {
    enable = true;
    environmentFile = config.sops.secrets."hermes-agent/env".path;
    telegramAllowedUsers = [123456789];
    openFirewall = false;

    settings = {
      agent.max_turns = 60;
    };
  };
}
