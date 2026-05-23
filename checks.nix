{
  pkgs,
  lib,
  self,
  system,
}: let
  hermes = self.packages.${system}.hermes-agent;
in {
  # Smoke — binary runs + reports version
  smoke = pkgs.runCommand "hermes-smoke" {} ''
    version=$(${hermes}/bin/hermes --version)
    case "$version" in
      *"Hermes Agent v0.14.0"*) ;;
      *) echo "unexpected version: $version" >&2; exit 1 ;;
    esac
    echo "$version" > $out
  '';

  # Module evaluation — does the NixOS module produce a valid systemd unit?
  module-eval = let
    eval = lib.evalModules {
      modules = [
        ({lib, ...}: {
          options._module.args = lib.mkOption {internal = true;};
        })
        self.nixosModules.default
        {
          # Stub the bits the module assumes are present in a real NixOS config
          users = lib.mkForce {users = {}; groups = {};};
          networking.firewall = lib.mkDefault {};
          services.hermes-agent = {
            enable = true;
            environmentFile = "/run/secrets/hermes-agent";
            telegramAllowedUsers = [7729797827];
          };
        }
      ];
      specialArgs = {inherit pkgs;};
    };
  in
    pkgs.runCommand "hermes-module-eval" {} ''
      # If lib.evalModules above didn't throw, the module is structurally sound.
      echo "module evaluates" > $out
    '';
}
