# hermes-flake

Nix flake packaging [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) for NixOS — declarative install, system service, optional container isolation.

Vendor-neutral defaults. Configure model backend, secrets, and platform behavior via module options. Ships:

- `packages.<system>.hermes-agent` — hermes 0.14.0 (3 CLIs: `hermes`, `hermes-acp`, `hermes-agent`).
- `packages.<system>.hermes-agent-full` — same with all upstream extras (voice, messaging, web, mcp, …).
- `nixosModules.default` — system service with sops-nix `EnvironmentFile`, btrfs subvolume bootstrap, hardening, healthcheck.
- `homeManagerModules.default` — per-user install for desktops.
- `checks.<system>.{smoke,module-eval}` — `nix flake check` covers binary + module validity.

Pinned to upstream `v2026.5.16` (v0.14.0).

## Quick run

    nix run github:ErikBPF/hermes-flake -- --version

## Why uv2nix

Hermes upstream uses `uv` and ships an exact-pinned `uv.lock`. `uv2nix` reads that lock as-is and derives the Python dep graph. Alternatives considered:

- **`buildPythonApplication`** — would require manual replication of 50+ deps from `uv.lock`. High drift risk.
- **`poetry2nix`** — wrong tool (hermes doesn't use Poetry).
- **PyPI sdist** — sdist usually drops `uv.lock`, so we'd lose the lockfile. The github tag at `v2026.5.16` is the same code PyPI ships *plus* the lockfile.

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

Each option maps to an upstream env var or `config.yaml` field. See [`docs/ENV_VARS.md`](docs/ENV_VARS.md) for the full upstream-truth-table.

### Core

| Option | Default | Purpose / Maps to |
|---|---|---|
| `enable` | false | Toggle the service |
| `package` | `flake.packages.hermes-agent` | Variant to run |
| `user` / `group` | `hermes` / `hermes` (UID/GID 10000) | Run identity — UID matches migrated Docker volumes |
| `dataDir` | `/var/lib/hermes-agent` | `HERMES_HOME` — persistent state (btrfs subvolume if FS supports it) |
| `environmentFile` | `null` | sops-rendered dotenv path → systemd `EnvironmentFile=` |
| `configFile` | `null` (uses generated) | `HERMES_CONFIG_FILE` |
| `settings` | `{}` | Nix attrset → `config.yaml`, merged into default |
| `soulFile` | `null` (uses bundled) | `HERMES_SOUL_FILE` |
| `profile` | `null` | `HERMES_PROFILE` — multi-profile selector |

### API server (port 8642 default)

| Option | Default | Env var |
|---|---|---|
| `openBindAddress` | `0.0.0.0` | `API_SERVER_HOST` |
| `apiPort` | `8642` | `API_SERVER_PORT` |
| `apiServerCorsOrigins` | `[]` | `API_SERVER_CORS_ORIGINS` (comma-joined) |
| `apiServerModelName` | `""` | `API_SERVER_MODEL_NAME` |
| `maxIterations` | `90` | `HERMES_MAX_ITERATIONS` |
| (env-only) | — | `API_SERVER_KEY` — set via sops EnvironmentFile |

### Webhook gateway (port 8644 default)

| Option | Default | Env var |
|---|---|---|
| `webhookPort` | `8644` | `WEBHOOK_PORT` |
| (env-only) | — | `WEBHOOK_SECRET` — set via sops EnvironmentFile (global HMAC fallback) |

Per-route HMAC secrets must be referenced via `WEBHOOK_<ROUTE>_SECRET` env vars and declared in `services.hermes-agent.settings.platforms.webhook.extra.routes.<name>.hmac_secret_env`. See [`docs/WEBHOOK_ROUTES.md`](docs/WEBHOOK_ROUTES.md).

### Telegram

| Option | Default | Env var |
|---|---|---|
| `telegramAllowedUsers` | `[]` | `TELEGRAM_ALLOWED_USERS` |
| `telegramAllowedChats` | `[]` | `TELEGRAM_ALLOWED_CHATS` |
| `telegramAllowedTopics` | `[]` | `TELEGRAM_ALLOWED_TOPICS` |
| (env-only via sops) | — | `HERMES_TELEGRAM_BOT_TOKEN` (bridged to `TELEGRAM_BOT_TOKEN`) |

### Dashboard (port 9119, off by default)

| Option | Default | Env var |
|---|---|---|
| `enableDashboard` | `false` | `HERMES_DASHBOARD=1` |
| `dashboardHost` | `127.0.0.1` | `HERMES_DASHBOARD_HOST` |
| `dashboardPort` | `9119` | `HERMES_DASHBOARD_PORT` |

### Model backend

| Option | Default | Env var |
|---|---|---|
| `openaiBaseUrl` | `https://api.openai.com/v1` | `OPENAI_BASE_URL` |

### systemd hardening

| Option | Default | Purpose |
|---|---|---|
| `memoryMax` | `2G` | `MemoryMax=` |
| `cpuQuota` | `200%` | `CPUQuota=` |
| `openFirewall` | `false` | Open `apiPort` + `webhookPort` |

## sops-nix integration

Required env keys (filename of the secret matters less than these key names inside it — upstream hermes reads them directly):

    LITELLM_API_KEY=...
    OPENAI_API_KEY=...                       # same as LITELLM_API_KEY
    OPENROUTER_API_KEY=...
    API_SERVER_KEY=...                       # 48-char hex; required when binding 0.0.0.0
    HERMES_TELEGRAM_BOT_TOKEN=...            # renamed from TELEGRAM_BOT_TOKEN
    HERMES_DISCORD_BOT_TOKEN=...             # renamed from DISCORD_BOT_TOKEN
    EXA_API_KEY=...

The module bridges `HERMES_*_BOT_TOKEN` → upstream-expected `TELEGRAM_BOT_TOKEN` / `DISCORD_BOT_TOKEN` at process start via the `ExecStart` wrapper. The `HERMES_` prefix is recommended when your secret store also serves a notification stack (Grafana / Healthchecks / etc.) that already uses the unprefixed `TELEGRAM_BOT_TOKEN` name — the prefix prevents collision.

### One-time secret seeding

    # define encrypted secrets
    sops secrets/hermes.env.sops
    # paste keys per above, save (sops auto-encrypts)

    # rebuild — secret lands at /run/secrets/hermes-agent
    sudo nixos-rebuild switch

## config.yaml

Built-in default is vendor-neutral: OpenRouter as the model provider, `anthropic/claude-opus-4.6` as the default model, 60-turn max, memory + wiki provider enabled, `redact_pii` on, all hardening directives applied. Override piecemeal via `services.hermes-agent.settings`:

    services.hermes-agent.settings = {
      model.default = "claude-opus-4-7";
      agent.max_turns = 120;
      memory.nudge_interval = 5;
    };

Or replace wholesale with a literal file:

    services.hermes-agent.configFile = ./config.yaml;

Runtime values for `model.api_key`, `${OPENAI_API_KEY}`, etc come from `EnvironmentFile`. The YAML retains the `${VAR}` syntax — upstream hermes interpolates at load time.

## SOUL.md

Personality contract. Bundled default is a neutral placeholder — override with your own:

    services.hermes-agent.soulFile = ./my-soul.md;

## Migration from Docker

If you're migrating from the upstream Docker compose deployment, see [docs/MIGRATION.md](docs/MIGRATION.md).

## Caveats

- **Lazy-installed deps.** Hermes installs `python-telegram-bot[webhooks]`, `discord.py[voice]`, ripgrep, ffmpeg, node, browsers on first use inside `$HERMES_HOME` (= `dataDir`). This is intentional — `dataDir` is writable, the nix store is not. Hardening uses `ProtectSystem=strict` + `ReadWritePaths=[dataDir]` so this works. `ProtectHome=read-only` means hermes can NOT write to `~/.hermes` — `HERMES_HOME=dataDir` redirects everything into mutable storage.

- **No Playwright/Chromium pre-install.** First browser-tool invocation triggers a download (~150 MB). Tolerable for a 24/7 host but slows the first such turn.

- **Healthcheck.** The bundled `hermes-agent-healthcheck.timer` polls `/health` every 60s. It does NOT restart on failure — only emits a journal log. Wire to your monitoring stack (Alloy/Grafana) if you want pager behavior.

- **Single instance.** `gateway run --replace` ensures only one running gateway per dataDir. Don't run the systemd service AND a CLI session simultaneously against the same dataDir.

## CI cache

Cache hits via [magic-nix-cache](https://github.com/DeterminateSystems/magic-nix-cache-action) on each CI run. Free, GH-Actions-bounded (10 GB, 7-day eviction). For dedicated substitution, switch to [Garnix](https://garnix.io) (free for public repos) or self-host [Attic](https://github.com/zhaofengli/attic).

## Versions

| flake tag | hermes-agent | python | nixpkgs channel |
|---|---|---|---|
| `main` | v0.14.0 (2026.5.16) | 3.13 | nixos-unstable |

Bump procedure: edit `hermes-agent-src.url` in `flake.nix`, run `nix flake update hermes-agent-src`, rebuild, fix overrides if a new C-ext dep appears.

## License

MIT.

## Isolation options

- **Bare-metal NixOS module** — `nixosModules.default` (recommended for trusted hosts)
- **nixos-container wrapper** — `nixosModules.hermes-agent-container` (Docker-like systemd-nspawn isolation, fully declarative)
- **podman/microvm.nix** — sketched in [docs/ISOLATION.md](docs/ISOLATION.md)

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
| `smoke` | binary runs, prints v0.14.0, all 3 entry points exist | ~2 min cold, free warm |
| `smoke-full` | full variant builds | ~5 min cold |
| `config-yaml-schema` | rendered YAML has `discord:` at top-level, `platforms.{api_server,webhook,telegram}` registered | ~1s |
| `config-yaml-override` | `settings = { agent.max_turns = 120; }` overrides apply correctly | ~1s |
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
- [docs/CLIENT.md](docs/CLIENT.md) — laptop client patterns (A/B/C/D)
- [docs/UPSTREAM_PR.md](docs/UPSTREAM_PR.md) — plan for contributing back to NousResearch
- [example/configuration.nix](example/configuration.nix) — bare-metal NixOS host config
- [example/container.nix](example/container.nix) — nixos-container variant
