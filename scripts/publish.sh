#!/usr/bin/env bash
# One-shot publisher — call AFTER `gh auth login`. Applies the GitHub repo
# settings + tags + release that CONTRIBUTING.md → "Publishing a release"
# enumerates. Idempotent: safe to re-run; existing settings are overwritten.
#
# Usage: ./scripts/publish.sh v0.1.0
set -euo pipefail

readonly REPO="ErikBPF/hermes-flake"
readonly DESC='Third-party Nix flake for NousResearch/hermes-agent — NixOS service module + container/microvm/podman wrappers + per-user home-manager module'
readonly TOPICS=(
    nix
    nix-flake
    nixos
    nixos-module
    hermes-agent
    nousresearch
    llm
    ai-agent
    anthropic
    openrouter
    litellm
    sops-nix
    microvm
    systemd-nspawn
    podman
    oci-container
    uv2nix
    pyproject-nix
)

VERSION="${1:-}"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 vX.Y.Z" >&2
    exit 1
fi

if ! command -v gh >/dev/null; then
    echo "gh CLI not installed — nix shell -p gh" >&2
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "gh not authenticated — run: gh auth login" >&2
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "Working tree dirty — commit or stash before publishing" >&2
    exit 1
fi

echo "→ Setting repo description + topics"
gh repo edit "$REPO" --description "$DESC"
gh repo edit "$REPO" $(printf -- '--add-topic %s ' "${TOPICS[@]}")

echo "→ Enabling Discussions"
gh repo edit "$REPO" --enable-discussions

echo "→ Tagging $VERSION"
if git rev-parse "$VERSION" >/dev/null 2>&1; then
    echo "  tag $VERSION already exists locally; skipping create"
else
    git tag -a "$VERSION" -m "Release $VERSION"
fi

echo "→ Pushing tag"
git push origin "$VERSION"

echo "→ Cutting GitHub release"
if gh release view "$VERSION" -R "$REPO" >/dev/null 2>&1; then
    echo "  release $VERSION already exists; skipping create"
else
    gh release create "$VERSION" -R "$REPO" \
        --title "$VERSION" \
        --notes-file <(awk -v ver="## $VERSION" '
            $0 == "## Unreleased" || $0 == ver { flag=1; next }
            /^## / && flag { exit }
            flag { print }
        ' CHANGELOG.md)
fi

cat <<EOF

✓ Repo description, topics, discussions, tag, and release applied.

Manual next steps (not API-driven):
  - Upload Social preview image: https://github.com/$REPO/settings
  - Announce on NixOS Discourse: https://discourse.nixos.org/c/announcements/8
  - PR to nix-community/awesome-nix
  - Create NixOS Wiki page for "Hermes Agent"
  - Claim flake at https://flakehub.com
EOF
