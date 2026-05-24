# Changelog

Conventional Commits in the git log; this file groups by release.

## Unreleased

### Added
- `nixosModules.hermes-agent-microvm` — KVM-isolated guest with its own kernel, virtio-9p shares for `dataDir` + secrets, swappable hypervisor (qemu / cloud-hypervisor / firecracker / crosvm / kvmtool).
- `nixosModules.hermes-agent-container` — systemd-nspawn isolation wrapper.
- `overlays.default` — `pkgs.hermes-agent` for downstream consumers.
- `extras` option (NixOS + home-manager) and `pkgs.hermes-agent.withExtras [ ... ]` passthru — pick any subset of upstream `pyproject.toml` extras at build time. `availableExtras` enumerates the list; unknown names error at eval time.
- `extraServiceDeps` option — extra systemd `Wants` / `After` for site-specific deps.
- `enableHealthcheck` + `healthcheckInterval` — toggle / retune the `/health` poll.
- `services.hermes-agent-container.extraServiceOptions` — opaque attrset forwarded to the inner `services.hermes-agent`.
- Hourly auto-update workflow (`.github/workflows/update-hermes-agent.yml`) tracking upstream `NousResearch/hermes-agent` releases via `scripts/update-version.sh`.
- Dependabot config for Actions pins.
- `devShells.default` — nix tooling (alejandra, statix, deadnix, nil) + update flow tools.
- `Justfile` — `just build`, `just check`, `just update`, `just extras`, etc.
- Tests: `smoke`, `smoke-full`, `config-yaml-schema`, `config-yaml-override`, `closure-size` (guards under 1500 MB), `nixos-module` (VM).
- Docs: `ENV_VARS.md`, `WEBHOOK_ROUTES.md`, `ISOLATION.md`, `CLIENT.md`, `MIGRATION.md`, `STATE.md`, `SOPS.md`, `RELEASING.md`, `CONTRIBUTING.md`.

### Changed
- `openBindAddress` default: `0.0.0.0` → `127.0.0.1` (matches upstream; public binding is now opt-in).
- `memoryMax` / `cpuQuota` defaults: `"2G"` / `"200%"` → `null` (uncapped; explicit caps for hosts that want them).
- Smoke check no longer hardcodes the hermes-agent version — reads it from upstream's `pyproject.toml` at eval time so the auto-bump cron doesn't need to touch tests.
- Discord platform settings rendered at YAML top-level (was incorrectly under `platforms.discord`).
- `module.nix` ExecStart bridges `HERMES_*_BOT_TOKEN` → upstream-expected `TELEGRAM_BOT_TOKEN` / `DISCORD_BOT_TOKEN` so the same secret file can be shared with a separate notification stack.
- `config.yaml.nix` defaults are vendor-neutral (provider=auto, OpenRouter URL, `claude-opus-4.6`); consumers add site-specific routing via `services.hermes-agent.settings`.

### Fixed
- Home-manager module exports `extraEnvironment` via `programs.{bash,fish}.{initExtra,shellInit}` because `home.sessionVariables` does not reliably reach interactive fish shells.
- `overrides.nix` patches the Alibaba SDK chain (pulled by the `dingtalk` extra) and `python-olm` (pulled by `matrix`): inject `setuptools` + `wheel` into `nativeBuildInputs` for sdist packages that use `setuptools.build_meta:__legacy__` without declaring it.
- `closure-size` check uses `pkgs.closureInfo` instead of `nix-store --query` (sandbox-safe).

## Initial scaffold

Pinned upstream at `v2026.5.16` (`hermes-agent` 0.14.0).
