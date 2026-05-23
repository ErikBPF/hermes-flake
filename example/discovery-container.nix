{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.hermes-flake.nixosModules.hermes-agent-container
    inputs.sops-nix.nixosModules.sops
  ];

  sops = {
    defaultSopsFile = ./secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets."hermes-agent/env" = {
      format = "dotenv";
      sopsFile = ./secrets-hermes.env.sops;
      # 0440 + group hermes so UID 10000 inside the container can read it
      # (containers have their own /etc/{passwd,group} so we rely on numeric UID).
      mode = "0440";
      path = "/run/secrets/hermes-agent";
    };
  };

  services.hermes-agent-container = {
    enable = true;
    containerName = "hermes";

    # Default. Simpler. SWAG keeps working with set $upstream_app 127.0.0.1;
    # If you want maximum isolation, flip to true + adjust SWAG conf.
    privateNetwork = false;

    hostDataDir = "/var/lib/hermes-agent";
    hostSecretsPath = config.sops.secrets."hermes-agent/env".path;

    telegramAllowedUsers = [7729797827];
    settings.agent.max_turns = 60;
  };
}
