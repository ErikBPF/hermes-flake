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
  # Targeted optionals — pick a curated subset to avoid pulling Alibaba /
  # Feishu Chinese-platform SDKs that fail to build cleanly under uv2nix.
  optionals = workspace.deps.optionals or {};
  pick = names: lib.foldl' (acc: n: acc // (optionals.${n} or {})) {} names;
in {
  # Base — no optional extras.
  hermes-agent = mkHermesPkg {
    name = "hermes-agent";
    depGroups = workspace.deps.default;
  };

  # Voice — STT (faster-whisper) + audio (sounddevice).
  hermes-agent-voice = mkHermesPkg {
    name = "hermes-agent-voice";
    depGroups = workspace.deps.default // pick ["voice"];
  };

  # Western messaging gateways only — Telegram, Discord, Slack, Signal,
  # WhatsApp, Matrix. Excludes DingTalk + Feishu (transitive Alibaba SDK
  # build issues under uv2nix; opt-in via hermes-agent-full if you need them).
  hermes-agent-messaging = mkHermesPkg {
    name = "hermes-agent-messaging";
    depGroups = workspace.deps.default // pick ["messaging"];
  };

  # Web — FastAPI + uvicorn for the gateway's API server enhancements.
  hermes-agent-web = mkHermesPkg {
    name = "hermes-agent-web";
    depGroups = workspace.deps.default // pick ["web"];
  };

  # MCP — Anthropic Model Context Protocol support.
  hermes-agent-mcp = mkHermesPkg {
    name = "hermes-agent-mcp";
    depGroups = workspace.deps.default // pick ["mcp"];
  };

  # Bedrock — AWS Bedrock provider.
  hermes-agent-bedrock = mkHermesPkg {
    name = "hermes-agent-bedrock";
    depGroups = workspace.deps.default // pick ["bedrock"];
  };

  # All extras (including DingTalk + Feishu). May fail to build until upstream
  # Alibaba SDK sdist build issues are resolved or overridden in overrides.nix.
  # Most users want one of the targeted variants above instead.
  hermes-agent-full = mkHermesPkg {
    name = "hermes-agent-full";
    depGroups = workspace.deps.all;
  };
}
