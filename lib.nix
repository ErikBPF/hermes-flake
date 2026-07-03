# nix/lib.nix — Shared helpers for npm workspace builds
#
# Adapted from upstream NousResearch/hermes-agent nix/lib.nix.
# All npm packages in the upstream repo are workspace members sharing a single
# root package-lock.json.  mkNpmPassthru provides the shared src, npmDeps,
# npmRoot, and npmConfigHook so individual .nix files don't duplicate them.
{
  pkgs,
  npm-lockfile-fix,
  nodejs,
  hermesSrc,
}:
let
  # npm dependencies for the workspace, resolved from the lockfile.
  npmDeps = pkgs.importNpmLock.importNpmLock { npmRoot = hermesSrc; };
in
{
  # Returns a buildNpmPackage-compatible attrs set that provides:
  #   src, npmDeps, npmRoot      — workspace source + importNpmLock dep set
  #   npmConfigHook              — importNpmLock's offline `npm install` hook
  #   nativeBuildInputs          — [ updateLockfileScript ] (list, prepend with ++ for more)
  #   passthru.packageJsonPath   — relative path to this workspace's package.json
  #   nodejs                     — fixed nodejs version for all packages
  mkNpmPassthru =
    {
      folder, # repo-relative folder with package.json, e.g. "apps/desktop"
      attr, # flake package attr, e.g. "desktop"
      ...
    }:
    let
    in
    {
      inherit npmDeps nodejs;
      src = hermesSrc;
      npmConfigHook = pkgs.importNpmLock.npmConfigHook;
      npmRoot = ".";

      ELECTRON_SKIP_BINARY_DOWNLOAD = 1;

      nativeBuildInputs = [
        (pkgs.writeShellScriptBin "update_${attr}_lockfile" ''
          set -euox pipefail

          REPO_ROOT=$(git rev-parse --show-toplevel)

          # All workspace packages share the root lockfile.
          cd "$REPO_ROOT"
          rm -rf node_modules/
          ${pkgs.lib.getExe' nodejs "npm"} cache clean --force
          CI=true ${pkgs.lib.getExe' nodejs "npm"} install --workspaces
          ${pkgs.lib.getExe npm-lockfile-fix} ./package-lock.json

          nix build .#${attr}
          echo "Lockfile updated and build verified for .#${attr}"
        '')
      ];

      passthru = {
        packageJsonPath = "${folder}/package.json";
      };
    };
}
