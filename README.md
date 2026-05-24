# hermes-flake

[![build](https://github.com/ErikBPF/hermes-flake/actions/workflows/build.yml/badge.svg)](https://github.com/ErikBPF/hermes-flake/actions/workflows/build.yml)
[![upstream](https://img.shields.io/github/v/release/NousResearch/hermes-agent?label=hermes-agent&color=blue)](https://github.com/NousResearch/hermes-agent/releases)
[![license](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![NixOS](https://img.shields.io/badge/NixOS-unstable-blue?logo=nixos)](https://nixos.org)

Nix flake packaging [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent). Vendor-neutral defaults, four isolation modes, hourly upstream tracker.

## Quick start

    nix run github:ErikBPF/hermes-flake -- --version

## Outputs

| Output | What |
|---|---|
| `packages.<sys>.hermes-agent` | Base — pick extras via `.withExtras [ ... ]` |
| `packages.<sys>.hermes-agent-full` | Every declared extra |
| `nixosModules.default` | System service, bare-metal |
| `nixosModules.hermes-agent-container` | systemd-nspawn isolation |
| `nixosModules.hermes-agent-podman` | OCI container (podman or docker) |
| `nixosModules.hermes-agent-microvm` | KVM-isolated guest |
| `homeManagerModules.default` | Per-user install |
| `overlays.default` | `pkgs.hermes-agent` everywhere |

## Install as a NixOS service

    {
      inputs.hermes-flake.url = "github:ErikBPF/hermes-flake";

      outputs = { nixpkgs, hermes-flake, sops-nix, ... }: {
        nixosConfigurations.host = nixpkgs.lib.nixosSystem {
          modules = [
            sops-nix.nixosModules.sops
            hermes-flake.nixosModules.default
            ({ config, ... }: {
              sops.secrets."hermes-agent/env" = {
                sopsFile = ./secrets/hermes.env.sops;
                format = "dotenv";
                owner = "hermes";
                mode = "0440";
              };
              services.hermes-agent = {
                enable = true;
                environmentFile = config.sops.secrets."hermes-agent/env".path;
                extras = [ "voice" "anthropic" "mcp" ];
                telegramAllowedUsers = [ 123456789 ];
              };
            })
          ];
        };
      };
    }

Full example: [`example/configuration.nix`](example/configuration.nix). Container variant: [`example/container.nix`](example/container.nix).

## Extras

`hermes-agent` ships base only. Pick optional extras at build time:

    # discover
    nix eval github:ErikBPF/hermes-flake#hermes-agent.availableExtras

    # build with specific extras
    nix build --impure --expr \
      '(builtins.getFlake "github:ErikBPF/hermes-flake").packages.x86_64-linux.hermes-agent.withExtras [ "voice" "anthropic" ]'

    # or via module option
    services.hermes-agent.extras = [ "voice" "anthropic" "mcp" ];

Unknown extra names error at eval time. See [`docs/ENV_VARS.md`](docs/ENV_VARS.md) for full reference.

## Module options

High-level groups (canonical reference is [`docs/ENV_VARS.md`](docs/ENV_VARS.md)):

- **Core**: `enable`, `package`, `extras`, `user`/`group`, `dataDir`, `environmentFile`, `configFile`, `settings`, `soulFile`, `profile`
- **API server (8642)**: `openBindAddress`, `apiPort`, `apiServerCorsOrigins`, `apiServerModelName`, `maxIterations`
- **Webhook gateway (8644)**: `webhookPort` + routes via `settings.platforms.webhook.extra.routes` ([`docs/WEBHOOK_ROUTES.md`](docs/WEBHOOK_ROUTES.md))
- **Telegram**: `telegramAllowedUsers`, `telegramAllowedChats`, `telegramAllowedTopics`
- **Dashboard (9119, off)**: `enableDashboard`, `dashboardHost`, `dashboardPort`
- **Model backend**: `openaiBaseUrl`
- **systemd**: `memoryMax`, `cpuQuota`, `openFirewall`, `extraServiceDeps`. Baseline process safety (`NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, `ProtectHome=read-only`, `ReadWritePaths=[dataDir]`) always applied. Kernel-level hardening is **not** prescribed — apply via standard `systemd.services.hermes-agent.serviceConfig` override.
- **Healthcheck**: `enableHealthcheck`, `healthcheckInterval`

Inspect interactively:

    nix repl
    > :lf .
    > nixosModules.default { config = {}; lib = (import <nixpkgs> {}).lib; pkgs = (import <nixpkgs> {}); }.options.services.hermes-agent

## Caveats

- **Lazy-installed deps.** Hermes installs `python-telegram-bot[webhooks]`, `discord.py[voice]`, ripgrep, ffmpeg, node, browsers on first use inside `$HERMES_HOME` (= `dataDir`). `ProtectSystem=strict` + `ReadWritePaths=[dataDir]` allows this; `ProtectHome=read-only` + `HERMES_HOME=dataDir` keeps writes inside mutable storage.
- **Playwright/Chromium.** First browser-tool invocation downloads ~150 MB into `dataDir`.
- **Single instance per dataDir.** `gateway run --replace` ensures only one running gateway. Don't run the systemd service AND a CLI session against the same dataDir.

## Development

    nix develop                                   # dev shell
    just                                          # list recipes
    just build                                    # base
    just build-extras "voice anthropic mcp"       # custom
    just check / check-full / check-vm
    just update-check / update / update-to VERSION
    just extras / fmt / lint

## See also

- [`docs/ENV_VARS.md`](docs/ENV_VARS.md) — upstream-audited env var truth table
- [`docs/ISOLATION.md`](docs/ISOLATION.md) — bare-metal / nspawn / podman / microvm trade-offs
- [`docs/CLIENT.md`](docs/CLIENT.md) — client patterns (local CLI / delegated / web / messaging / ACP)
- [`docs/SOPS.md`](docs/SOPS.md) — sops-nix integration recipe
- [`docs/WEBHOOK_ROUTES.md`](docs/WEBHOOK_ROUTES.md) — per-route HMAC pattern
- [`docs/STATE.md`](docs/STATE.md) — what persists in `dataDir`, backup procedure
- [`docs/MIGRATION.md`](docs/MIGRATION.md) — Docker → NixOS migration
- [`docs/RELEASING.md`](docs/RELEASING.md) — maintainer release flow
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — contributor guide
- [`SECURITY.md`](SECURITY.md) — vuln reporting + threat model
- [`CHANGELOG.md`](CHANGELOG.md) — release notes
