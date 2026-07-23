# desktop.nix — Hermes Desktop (Electron) app build + wrapper
#
# Adapted from upstream NousResearch/hermes-agent nix/desktop.nix.
#
# `hermesAgent` is the fully-built hermes-agent package — it ships the
# `hermes` binary with the venv, runtime PATH, bundled skills/plugins, etc.
# already wired up.  We point the desktop at it via the existing
# `HERMES_DESKTOP_HERMES` override env var, so the desktop's resolver
# uses our fully wrapped binary at step 4 ("existing Hermes CLI").
# No reimplementation of the agent resolution in this wrapper.
{
  pkgs,
  lib,
  stdenv,
  makeWrapper,
  hermesNpmLib,
  electron,
  hermesAgent,
  ...
}: let
  desktopItem = pkgs.makeDesktopItem {
    name = "hermes-desktop";
    desktopName = "Hermes Agent";
    comment = "Autonomous AI agent by NousResearch";
    exec = "hermes-desktop";
    icon = "hermes-desktop";
    terminal = false;
    categories = ["Utility" "ArtificialIntelligence" "Network"];
    startupNotify = true;
    startupWMClass = "hermes";
  };
in let
  npm = hermesNpmLib.mkNpmPassthru {
    folder = "apps/desktop";
    attr = "desktop";
    pname = "hermes-desktop";
  };

  packageJson = builtins.fromJSON (builtins.readFile (npm.src + "/apps/desktop/package.json"));
  inherit (packageJson) version;

  # Build the renderer (dist/ + electron/ + package.json).
  renderer = pkgs.buildNpmPackage (
    npm
    // {
      pname = "hermes-desktop-renderer";
      inherit version;
      doCheck = true;

      buildPhase = ''
        runHook preBuild

        # write-build-stamp.cjs replacement.  Packaged Electron reads this
        # at first-launch to pin the install.ps1 git ref; informational in
        # nix builds (the backend comes from the derivation directly).
        mkdir -p apps/desktop/build
        echo '{"schemaVersion":1,"commit":"nix","branch":"nix","dirty":false,"source":"nix"}' > apps/desktop/build/install-stamp.json

        # patch shebangs in node_modules/.bin so npm exec can find the
        # nix-store equivalents of /usr/bin/env (which doesn't exist in the sandbox)
        patchShebangs .

        pushd apps/desktop
          npm rebuild node-pty --build-from-source

          npm exec tsc -b
          npm exec vite build
          node scripts/bundle-electron-main.mjs
          node scripts/stage-native-deps.mjs
        popd

        runHook postBuild
      '';

      checkPhase = ''
        runHook preCheck

        pushd apps/desktop

          npm run postbuild

          # validate staged node-pty native binary is present
          STAGED_PTY_NODE="./dist/node_modules/node-pty/build/Release/pty.node"

          if [ ! -f "$STAGED_PTY_NODE" ]; then
            echo "FATAL: Missing staged node-pty native binary at $STAGED_PTY_NODE"
            echo "node-pty must be compiled natively"
            exit 1
          fi

        popd

        runHook postCheck
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p $out
        # vite writes to apps/desktop/dist/ (we cd'd there in buildPhase).
        # apps/desktop/build was created before the cd.  electron/ is source.
        cp -rn apps/desktop/dist $out/
        cp -rn apps/desktop/electron $out/

        cp -n apps/desktop/build/install-stamp.json $out/

        cp -n apps/desktop/package.json $out/
        runHook postInstall
      '';
    }
  );
in
  # Electron wrapper: nixpkgs' electron binary pointed at the renderer dir.
  stdenv.mkDerivation {
    pname = "hermes-desktop";
    inherit version;

    dontUnpack = true;
    dontBuild = true;

    nativeBuildInputs = [makeWrapper];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share/hermes-desktop $out/bin
      cp -r ${renderer}/* $out/share/hermes-desktop/

      # Standard nixpkgs pattern for electron-builder apps: patch process.resourcesPath
      # to point to the app's directory. In Nix, unpackaged electron defaults this
      # to the electron distribution's resources path, breaking extraResources lookups.
      substituteInPlace $out/share/hermes-desktop/dist/electron-main.mjs \
        --replace-fail "process.resourcesPath" "'$out/share/hermes-desktop'"

      # Wrap the nixpkgs electron binary to launch our app.  Set
      # HERMES_DESKTOP_HERMES to the absolute path of the nix-built `hermes`
      # binary so the desktop's resolver step 4 ("existing Hermes CLI on
      # PATH") uses our fully wrapped binary — venv with all deps,
      # bundled skills/plugins, runtime PATH (ripgrep/git/ffmpeg/etc).
      # No reimplementation of the agent resolver in the wrapper.
      makeWrapper ${electron}/bin/electron $out/bin/hermes-desktop \
        --add-flags "$out/share/hermes-desktop" \
        --set HERMES_DESKTOP_HERMES "${hermesAgent}/bin/hermes" \
        --set ELECTRON_IS_DEV 0

      # Install .desktop file so GNOME and other desktop environments
      # can discover the app in the application menu.
      cp -r ${desktopItem}/share/applications $out/share/

      # Install app icon to the hicolor icon theme so the .desktop file
      # can resolve it.  The renderer ships a 1254×1254 hermes.png.
      mkdir -p $out/share/icons/hicolor/512x512/apps
      cp $out/share/hermes-desktop/dist/hermes.png $out/share/icons/hicolor/512x512/apps/hermes-desktop.png

      runHook postInstall
    '';

    passthru = {
      inherit (renderer.passthru) packageJsonPath;
    };

    meta = with lib; {
      description = "Native Electron desktop shell for Hermes Agent";
      homepage = "https://github.com/NousResearch/hermes-agent";
      license = licenses.mit;
      platforms = platforms.unix;
      mainProgram = "hermes-desktop";
    };
  }
