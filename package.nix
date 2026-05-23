{
  pkgs,
  lib,
  inputs,
  system,
}: let
  # Source pin: github tag rather than PyPI sdist.
  # Why: uv2nix consumes the uv.lock from the source tree to derive the dep
  # graph. PyPI sdists historically omit uv.lock (it's a dev-time artifact).
  # The github tag at v2026.5.16 contains the same code that PyPI ships PLUS
  # uv.lock, so reproducibility is equivalent and we get the lockfile for free.
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

  mkHermesVenv = depGroups:
    pythonSet.mkVirtualEnv "hermes-agent-env" depGroups;

  mkHermesPkg = {
    name,
    depGroups,
  }: let
    venv = mkHermesVenv depGroups;
  in
    pkgs.runCommandLocal name {
      meta = {
        description = "NousResearch hermes-agent (${name})";
        homepage = "https://github.com/NousResearch/hermes-agent";
        license = lib.licenses.mit;
        mainProgram = "hermes";
        platforms = lib.platforms.unix;
      };
      passthru = {
        inherit venv python;
        inherit (workspace) deps;
      };
    } ''
      mkdir -p $out/bin
      for bin in hermes hermes-agent hermes-acp; do
        if [ -x ${venv}/bin/$bin ]; then
          ln -s ${venv}/bin/$bin $out/bin/$bin
        fi
      done
    '';
in {
  hermes-agent = mkHermesPkg {
    name = "hermes-agent";
    depGroups = workspace.deps.default;
  };

  hermes-agent-full = mkHermesPkg {
    name = "hermes-agent-full";
    depGroups = workspace.deps.all;
  };
}
