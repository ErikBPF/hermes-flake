{
  pkgs,
  lib,
  inputs,
  system,
}: let
  hermesSrc = inputs.hermes-agent-src;
  python = pkgs.python314;
  upstreamLock = (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.hermes-agent-src;
  releaseVersion = lib.removePrefix "v" upstreamLock.original.ref;
  # Match upstream nix/hermes-agent.nix: immutable Nix builds own provenance.
  installStamp = assert lib.assertMsg
  (builtins.match "v[0-9]+\\.[0-9]+\\.[0-9]+(\\.[0-9]+)?" upstreamLock.original.ref
    != null
    && hermesSrc.rev == upstreamLock.locked.rev)
  "Hermes release identity requires a stable locked tag and matching source revision";
    pkgs.writeText "hermes-install-stamp.json" (builtins.toJSON {
      schemaVersion = 2;
      commit = hermesSrc.rev;
      commitDate = upstreamLock.locked.lastModified;
      branch = null;
      dirty = false;
      builtAt = null;
      baseVersion = releaseVersion;
      displayVersion = releaseVersion;
      distance = 0;
      source = "nix";
      distribution = "nix";
      updateMechanism = "external";
      payload = "bootstrap";
      tag = null;
    });

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
        (_final: prev: {
          hermes-agent = prev.hermes-agent.overrideAttrs (old: {
            postInstall =
              (old.postInstall or "")
              + ''
                cp ${installStamp} $out/${python.sitePackages}/install-stamp.json
              '';
          });
        })
      ]
    );

  # uv2nix exposes the list of declared extras (PEP 621
  # [project.optional-dependencies]) at workspace.deps.optionals.<pkg-name>.
  # Hermes is a single-package workspace, so all extras live under "hermes-agent".
  availableExtras =
    workspace.deps.optionals.hermes-agent or [];

  # The `wake` extra depends on `tflite-runtime` on Linux, but upstream only
  # publishes cp311 wheels for it (no cp312/cp313 wheels and no sdist). Since
  # this flake uses Python 3.14, the extra cannot be satisfied on Linux; drop it
  # from the eager "full" install so CI and default consumers don't break.
  # Users on Python 3.11 or Darwin can still request it explicitly via
  # `hermes-agent.withExtras [ "wake" ]`.
  # Mirror upstream's `[all]` extra set instead of installing every declared
  # extra: 0.23.1 moved opt-in backends (voice, wake, messaging, provider and
  # search packs) out of `[all]` so one broken wheel cannot fail every install.
  # Request those explicitly with `.withExtras`.
  fullExtras =
    lib.intersectLists
    ["acp" "cron" "google" "mcp" "pty" "sms" "uvloop" "web" "youtube"]
    availableExtras;

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
    in (pkgs.runCommandLocal name {
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
  packages = {
    # Base — no extras. Construct custom variants via .withExtras:
    #   pkgs.hermes-agent.withExtras [ "voice" "anthropic" ]
    hermes-agent = mkHermesPkg {
      name = "hermes-agent";
      extras = [];
    };

    # Every declared extra that is satisfiable on this platform/Python combo.
    # Build may fail on sdist-only packages that forget setuptools in
    # build-system.requires — see overrides.nix.
    hermes-agent-full = mkHermesPkg {
      name = "hermes-agent-full";
      extras = fullExtras;
    };
  };

  # Desktop (Electron) app — wraps the hermes-agent CLI with a native GUI.
  # Requires nodejs + electron at build time.
  hermesDesktop = let
    pmPackages = lib.filterAttrs (_: lib.isDerivation) (
      pkgs.callPackage (hermesSrc + "/nix/pm-packages.nix") {}
    );
    hermesNpmLib = pkgs.callPackage ./lib.nix {inherit pmPackages hermesSrc;};
    generatedIcons = pkgs.callPackage (hermesSrc + "/nix/icons.nix") {
      inherit (packages.hermes-agent) venv;
    };
  in
    pkgs.callPackage ./desktop.nix {
      inherit (pkgs) electron;
      inherit hermesNpmLib generatedIcons hermesSrc;
      installStampFile = installStamp;
      hermesAgent = packages.hermes-agent;
      python3 = python;
    };
in
  packages // {inherit hermesDesktop;}
