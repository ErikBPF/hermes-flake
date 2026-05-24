# hermes-flake

[![build](https://github.com/ErikBPF/hermes-flake/actions/workflows/build.yml/badge.svg)](https://github.com/ErikBPF/hermes-flake/actions/workflows/build.yml)
[![upstream](https://img.shields.io/github/v/release/NousResearch/hermes-agent?label=hermes-agent&color=blue)](https://github.com/NousResearch/hermes-agent/releases)
[![license](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![NixOS](https://img.shields.io/badge/NixOS-unstable-blue?logo=nixos)](https://nixos.org)


Nix flake packaging [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) for NixOS — declarative install, system service, optional container isolation.

Vendor-neutral defaults. Configure model backend, secrets, and platform behavior via module options. Ships:

- `packages.<system>.hermes-agent` — hermes 0.14.0 base (3 CLIs: `hermes`, `hermes-acp`, `hermes-agent`). Pick extras via `pkgs.hermes-agent.withExtras [ ... ]` or `services.hermes-agent.extras = [ ... ]`.
- `packages.<system>.hermes-agent-full` — every declared extra (may fail until upstream sdist build issues are patched).
- `nixosModules.default` — system service with sops-nix `EnvironmentFile`, btrfs subvolume bootstrap, hardening, healthcheck.
- `homeManagerModules.default` — per-user install for desktops.
- `checks.<system>.{smoke,smoke-full,config-yaml-schema,config-yaml-override,closure-size,nixos-module}` — `nix flake check` runs binary smoke, YAML schema validation, override-merge correctness, closure-size guard, and a NixOS VM module test.

Pinned to upstream `v2026.5.16` (v0.14.0).

## Picking extras

The flake ships a single `hermes-agent` package + a `withExtras` passthru that rebuilds the venv with chosen upstream extras included.

    # Inspect what's available
    nix eval github:ErikBPF/hermes-flake#hermes-agent.availableExtras

    # Build with specific extras
    nix build --impure --expr '(builtins.getFlake "github:ErikBPF/hermes-flake").packages.x86_64-linux.hermes-agent.withExtras [ "voice" "anthropic" "mcp" ]'

Available (currently): `acp`, `all`, `anthropic`, `bedrock`, `cli`, `computer-use`, `daytona`, `dev`, `dingtalk`, `edge-tts`, `exa`, `fal`, `feishu`, `firecrawl`, `google`, `hindsight`, `homeassistant`, `honcho`, `matrix`, `mcp`, `messaging`, `modal`, `parallel-web`, `pty`, `slack`, `sms`, `termux`, `termux-all`, `tts-premium`, `vercel`, `voice`, `web`, `youtube`.

In the modules:

    services.hermes-agent.extras = [ "voice" "anthropic" "mcp" ];
    # or for home-manager
    programs.hermes-agent.extras = [ "voice" ];

Unknown extras error at eval time. Some sdist-only extras (`dingtalk`, `feishu`, `matrix`) need `overrides.nix` entries — already patched for the Alibaba SDK chain pulled by `dingtalk`; add more as discovered.

## Quick run

    nix run github:ErikBPF/hermes-flake -- --version

## Build mechanism

Uses [`uv2nix`](https://github.com/pyproject-nix/uv2nix) to translate upstream's `uv.lock` into nix derivations. Source is pinned to the upstream `v2026.5.16` git tag (which carries `uv.lock`; PyPI sdists do not).

## NixOS service

    {
      inputs.hermes-flake.url = "github:ErikBPF/hermes-flake";

      outputs = { nixpkgs, hermes-flake, sops-nix, ... }: {
        nixosConfigurations.discovery = nixpkgs.lib.nixosSystem {
          modules = [
            sops-nix.nixosModules.sops
            hermes-flake.nixosModules.default
            {
              sops.secrets."hermes-agent/env" = {
                sopsFile = ./secrets/hermes.env.sops;
                format = "dotenv";
                owner = "hermes";
                mode = "0400";
              };

              services.hermes-agent = {
                enable = true;
                environmentFile = config.sops.secrets."hermes-agent/env".path;
                telegramAllowedUsers = [ 123456789 ];
                openFirewall = false;  # SWAG handles external access
                settings.agent.max_turns = 60;
              };
            }
          ];
        };
      };
    }

Full example at [`example/configuration.nix`](example/configuration.nix).

## Module options

Reference: **[`docs/ENV_VARS.md`](docs/ENV_VARS.md)** has the canonical truth-table of every option, its default, and which env var or `config.yaml` field it maps to. Inline `nix repl` introspection works too:

    nix repl
    > :lf .
    > nixosModules.default { config = {}; lib = (import <nixpkgs> {}).lib; pkgs = (import <nixpkgs> {}); }.options.services.hermes-agent

High-level groups:

- **Core**: `enable`, `package`, `user`/`group`, `dataDir`, `environmentFile`, `configFile`, `settings`, `soulFile`, `profile`
- **API server (port 8642)**: `openBindAddress`, `apiPort`, `apiServerCorsOrigins`, `apiServerModelName`, `maxIterations`
- **Webhook gateway (port 8644)**: `webhookPort` + per-route HMAC secrets via `settings.platforms.webhook.extra.routes` (see [`docs/WEBHOOK_ROUTES.md`](docs/WEBHOOK_ROUTES.md))
- **Telegram**: `telegramAllowedUsers`, `telegramAllowedChats`, `telegramAllowedTopics`
- **Dashboard (port 9119, off)**: `enableDashboard`, `dashboardHost`, `dashboardPort`
- **Model backend**: `openaiBaseUrl`
- **systemd**: `memoryMax`, `cpuQuota`, `openFirewall`, `extraServiceDeps`. Baseline process safety (`NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, `ProtectHome=read-only`, `ReadWritePaths=[dataDir]`) is always applied. Kernel-level hardening is **not** prescribed — apply via your host's standard `systemd.services.hermes-agent.serviceConfig = {...}` override.
- **Healthcheck**: `enableHealthcheck`, `healthcheckInterval`

## Secrets

Use sops-nix (or any secret store that renders to a dotenv file) to provide the runtime env. See [`docs/SOPS.md`](docs/SOPS.md) for the recipe and [`docs/ENV_VARS.md`](docs/ENV_VARS.md) for the complete key reference.

## config.yaml

Default config is vendor-neutral (OpenRouter, `claude-opus-4.6`, 60-turn max, wiki memory, `redact_pii` on). Override via `services.hermes-agent.settings` (deep-merges into the default) or `services.hermes-agent.configFile` (wholesale replace). See [`docs/ENV_VARS.md`](docs/ENV_VARS.md#things-that-are-not-env-vars-configyaml-only) for the YAML-only fields.

## SOUL.md

Personality contract loaded fresh per message. Override with `services.hermes-agent.soulFile = ./my-soul.md;`.

## Migration from Docker

See [`docs/MIGRATION.md`](docs/MIGRATION.md).

## Caveats

- **Lazy-installed deps.** Hermes installs `python-telegram-bot[webhooks]`, `discord.py[voice]`, ripgrep, ffmpeg, node, browsers on first use inside `$HERMES_HOME` (= `dataDir`). This is intentional — `dataDir` is writable, the nix store is not. Hardening uses `ProtectSystem=strict` + `ReadWritePaths=[dataDir]` so this works. `ProtectHome=read-only` means hermes can NOT write to `~/.hermes` — `HERMES_HOME=dataDir` redirects everything into mutable storage.

- **No Playwright/Chromium pre-install.** First browser-tool invocation triggers a download (~150 MB). Tolerable for a 24/7 host but slows the first such turn.

- **Healthcheck.** The bundled `hermes-agent-healthcheck.timer` polls `/health` every 60s. It does NOT restart on failure — only emits a journal log. Wire to your monitoring stack (Alloy/Grafana) if you want pager behavior.

- **Single instance.** `gateway run --replace` ensures only one running gateway per dataDir. Don't run the systemd service AND a CLI session simultaneously against the same dataDir.

## Development

Enter a dev shell with all the tooling pre-installed:

    nix develop

Common recipes via [`just`](https://github.com/casey/just):

    just                  # list recipes
    just build            # base build
    just build-extras "voice anthropic mcp"
    just check            # nix flake check --no-build
    just check-full       # everything except VM test
    just check-vm         # VM module test (needs KVM)
    just update-check     # is upstream ahead?
    just update           # apply latest upstream release
    just extras           # list available extras
    just fmt              # alejandra .
    just lint             # statix + deadnix

## CI cache

CI uses [magic-nix-cache](https://github.com/DeterminateSystems/magic-nix-cache-action) (GH Actions cache, 10 GB / 7-day eviction). No client setup required for `main` artifacts that fit the window.

## Versions

| flake tag | hermes-agent | python | nixpkgs channel |
|---|---|---|---|
| `main` | v0.14.0 (2026.5.16) | 3.13 | nixos-unstable |

Bump procedure: edit `hermes-agent-src.url` in `flake.nix`, run `nix flake update hermes-agent-src`, rebuild, fix overrides if a new C-ext dep appears.

## License

MIT.

## Isolation options

- **Bare-metal NixOS module** — `nixosModules.default` (trusted hosts)
- **nixos-container wrapper** — `nixosModules.hermes-agent-container` (systemd-nspawn isolation, fully declarative)
- **microvm wrapper** — `nixosModules.hermes-agent-microvm` (KVM-isolated guest with its own kernel)
- **podman/docker wrapper** — `nixosModules.hermes-agent-podman` (OCI container built via `dockerTools`, run via `virtualisation.oci-containers`)

Container quickstart:

    services.hermes-agent-container = {
      enable = true;
      containerName = "hermes";
      privateNetwork = false;  # share host net; flip to true for stronger isolation
      hostSecretsPath = config.sops.secrets."hermes-agent/env".path;
      telegramAllowedUsers = [ 123456789 ];
    };

Full example at [example/container.nix](example/container.nix).

## Client setup (laptop / per-user)

See [docs/CLIENT.md](docs/CLIENT.md). Summary: each hermes install has its own brain. Either run a per-workstation local CLI (own brain, shared model backend) or point local clients at a remote API server (Pattern B in CLIENT.md).

## Tests

`nix flake check` covers:

| Check | What it verifies | Cost |
|---|---|---|
| `smoke` | binary runs, all 3 entry points exist, version matches upstream `pyproject.toml` | ~2 min cold, free warm |
| `smoke-full` | full variant builds | ~5 min cold |
| `config-yaml-schema` | rendered YAML has `discord:` at top-level, `platforms.{api_server,webhook,telegram}` registered | ~1s |
| `config-yaml-override` | `settings = { agent.max_turns = 120; }` overrides apply correctly | ~1s |
| `closure-size` | base closure stays under 1500 MB (current ~280 MB) | ~5s |
| `nixos-module` | NixOS VM boots with module, asserts UID 10000, env vars exported, hardening directives present, bot-token bridge in ExecStart | ~5 min |

Run them locally:

    nix flake check --print-build-logs
    nix build .#checks.x86_64-linux.config-yaml-schema   # individual

CI runs all of them on `x86_64-linux` + `aarch64-linux`. VM test is `x86_64-linux` only (KVM-dependent).

## See also

- [docs/ENV_VARS.md](docs/ENV_VARS.md) — full upstream env var reference (audited)
- [docs/WEBHOOK_ROUTES.md](docs/WEBHOOK_ROUTES.md) — webhook routes + per-route HMAC pattern
- [docs/SOPS.md](docs/SOPS.md) — sops-nix integration recipe
- [docs/ISOLATION.md](docs/ISOLATION.md) — bare-metal vs container vs VM trade-offs
- [docs/CLIENT.md](docs/CLIENT.md) — client patterns (local CLI / delegated CLI / web / messaging / ACP)
- [docs/MIGRATION.md](docs/MIGRATION.md) — Docker → NixOS migration
- [docs/STATE.md](docs/STATE.md) — what persists in `dataDir`, backup procedure
- [docs/RELEASING.md](docs/RELEASING.md) — maintainer release flow
- [example/configuration.nix](example/configuration.nix) — bare-metal NixOS host config
- [example/container.nix](example/container.nix) — nixos-container variant
