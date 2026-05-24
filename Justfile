# hermes-flake recipes — `just --list` to discover

# Default: list recipes
default:
    @just --list

# Build the base hermes-agent package
build:
    nix build .#hermes-agent --print-build-logs

# Build the full variant (every extra — may fail until overrides catch up)
build-full:
    nix build .#hermes-agent-full --print-build-logs

# Build with specific extras (e.g. just build-extras "voice anthropic mcp")
build-extras EXTRAS:
    #!/usr/bin/env bash
    set -euo pipefail
    extras=$(printf '"%s" ' {{EXTRAS}})
    system=$(nix eval --raw --impure --expr 'builtins.currentSystem')
    nix build --impure --print-build-logs --expr \
      "(builtins.getFlake (toString ./.)).packages.\"$system\".hermes-agent.withExtras [ $extras ]"

# Run nix flake check (eval + critical checks, no heavy VM test)
check:
    nix flake check --no-build

# Run the full check matrix (smoke + schema + override + closure-size)
check-full:
    nix flake check

# Run the VM module test (slow — needs KVM)
check-vm:
    #!/usr/bin/env bash
    system=$(nix eval --raw --impure --expr 'builtins.currentSystem')
    nix build ".#checks.${system}.nixos-module" --print-build-logs

# Print the list of upstream-declared extras
extras:
    @nix eval --raw .#hermes-agent.availableExtras --apply 'lib: builtins.concatStringsSep ", " lib' 2>/dev/null \
      || nix eval --json .#hermes-agent.availableExtras

# Check whether upstream hermes-agent has a newer release
update-check:
    ./scripts/update-version.sh --check

# Apply the latest upstream release (bumps flake.nix + flake.lock, verifies build)
update:
    ./scripts/update-version.sh

# Pin to a specific upstream version
update-to VERSION:
    ./scripts/update-version.sh --version {{VERSION}}

# Format all Nix files in place
fmt:
    nix fmt -- .

# Lint
lint:
    statix check .
    deadnix --fail .

# Run a hermes binary from the built package
run *ARGS:
    nix run .# -- {{ARGS}}

# Show version
version:
    @nix run .# -- --version

# Clean build artifacts
clean:
    rm -rf result result-*
