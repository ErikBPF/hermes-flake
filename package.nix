{
  pkgs,
  lib,
  inputs,
  system,
}: let
  hermesSrc = inputs.hermes-agent-src;
  python = pkgs.python313;

  workspace = inputs.uv2nix.lib.workspace.loadWorkspace {
    workspaceRoot = hermesSrc;
  };

  overlay = workspace.mkPyprojectOverlay {
    sourcePreference = "wheel";
  };

  overrides = import ./overrides.nix {inherit pkgs lib;};

  pythonSet =
    (pkgs.callPackage inputs.pyproject-nix.build.packages {
      inherit python;
    })
    .overrideScope (
      lib.composeManyExtensions [
        inputs.pyproject-build-systems.overlays.default
        overlay
        overrides
      ]
    );

  # uv2nix exposes the list of declared extras (PEP 621
  # [project.optional-dependencies]) at workspace.deps.optionals.<pkg-name>.
  # Hermes is a single-package workspace, so all extras live under "hermes-agent".
  availableExtras =
    workspace.deps.optionals.hermes-agent or [];

  mkHermesPkg = {
    name,
    extras ? [],
  }: let
    unknown = lib.subtractLists availableExtras extras;
  in
    if unknown != []
    then
      throw ''
        hermes-flake: unknown extra(s): ${lib.concatStringsSep ", " unknown}
        Available: ${lib.concatStringsSep ", " availableExtras}
      ''
    else let
      venv =
        pythonSet.mkVirtualEnv "hermes-agent-env"
        {hermes-agent = extras;};
    in
    (pkgs.runCommandLocal name {
      meta = {
        description =
          "NousResearch hermes-agent"
          + lib.optionalString (extras != []) " (extras: ${lib.concatStringsSep "," extras})";
        homepage = "https://github.com/NousResearch/hermes-agent";
        license = lib.licenses.mit;
        mainProgram = "hermes";
        platforms = lib.platforms.unix;
      };
      passthru = {
        inherit venv python extras availableExtras;
        # `pkgs.hermes-agent.withExtras [ "voice" "anthropic" ]` returns a
        # derivation rebuilt with the listed extras. Used by the NixOS module's
        # `extras` option.
        withExtras = newExtras:
          mkHermesPkg {
            name =
              if newExtras == []
              then "hermes-agent"
              else "hermes-agent-with-${lib.concatStringsSep "-" newExtras}";
            extras = newExtras;
          };
      };
    } ''
      mkdir -p $out/bin
      for bin in hermes hermes-agent hermes-acp; do
        if [ -x ${venv}/bin/$bin ]; then
          ln -s ${venv}/bin/$bin $out/bin/$bin
        fi
      done
    '');
in {
  # Base — no extras. Construct custom variants via .withExtras:
  #   pkgs.hermes-agent.withExtras [ "voice" "anthropic" ]
  hermes-agent = mkHermesPkg {
    name = "hermes-agent";
    extras = [];
  };

  # Every declared extra. Build may fail on sdist-only packages that
  # forget setuptools in build-system.requires — see overrides.nix.
  hermes-agent-full = mkHermesPkg {
    name = "hermes-agent-full";
    extras = availableExtras;
  };
}
