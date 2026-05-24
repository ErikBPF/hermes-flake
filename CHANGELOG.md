# Changelog

All notable changes to this flake. Conventional Commits in the git log; this file groups by release.

## Unreleased

### Added
- Vendor-neutral defaults — `openaiBaseUrl` defaults to `api.openai.com`, `model.default = "anthropic/claude-opus-4.6"` via OpenRouter, neutral SOUL.md placeholder.
- `nixosModules.hermes-agent-container` — systemd-nspawn isolation wrapper.
- `overlays.default` — consumers can `pkgs.hermes-agent` after applying.
- `extraServiceDeps` option — extra systemd Wants/After for site-specific dependencies (Tailscale, sops-nix, etc.).
- Hourly auto-update workflow (`.github/workflows/update-hermes-agent.yml`) tracking upstream `NousResearch/hermes-agent` releases.
- `scripts/update-version.sh` — manual update path mirroring the CI workflow.
- Dependabot config for keeping Actions pins fresh.
- `docs/ENV_VARS.md` — upstream-audited env var truth table.
- `docs/WEBHOOK_ROUTES.md` — per-route HMAC pattern + sops integration.
- `docs/ISOLATION.md` — bare-metal / nspawn / microvm / podman trade-off matrix.
- `docs/CLIENT.md` — 5 client patterns (local CLI / delegated CLI / web / messaging / ACP).
- `docs/MIGRATION.md` — generic Docker → NixOS migration.
- `docs/STATE.md` — what persists, what's regenerated, backup procedure.
- `docs/SOPS.md` — sops-nix integration recipe.
- `CONTRIBUTING.md` — update cadence, manual update path, pinning ladder, testing matrix.
- Tests: `smoke`, `smoke-full`, `config-yaml-schema`, `config-yaml-override`, `nixos-module` (VM).

### Changed
- Smoke check no longer hardcodes the hermes-agent version string — reads from upstream's `pyproject.toml` at eval time.
- Discord platform settings rendered at YAML top-level (was incorrectly under `platforms.discord`).
- `module.nix` ExecStart bridges `HERMES_*_BOT_TOKEN` → upstream-expected `TELEGRAM_BOT_TOKEN` / `DISCORD_BOT_TOKEN` for env-file co-existence with notification stacks.

### Fixed
- Home-manager module exports `extraEnvironment` via `programs.{bash,fish}.{initExtra,shellInit}` because `home.sessionVariables` does not reliably reach interactive fish shells.
- `config.yaml.nix` no longer emits `auxiliary` / `model_aliases` / site-specific URLs by default — consumers add via `services.hermes-agent.settings`.

## Pre-history

This flake started life as a homelab-specific deployment tool tightly coupled to one operator's setup. All of that has been moved into the consuming NixOS configuration; this repo is now vendor-neutral and ready for downstream users.

Initial scaffold pinned upstream at `v2026.5.16` (`hermes-agent` 0.14.0).
