# hermes-flake

Nix flake packaging [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) for NixOS. Ships:

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
                telegramAllowedUsers = [ 7729797827 ];
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

| Option | Default | Purpose |
|---|---|---|
| `enable` | false | Toggle the service |
| `package` | `flake.packages.hermes-agent` | Variant to run |
| `user` / `group` | `hermes` / `hermes` (UID/GID 10000) | Run identity — UID matches migrated Docker volumes |
| `dataDir` | `/var/lib/hermes-agent` | Persistent state (btrfs subvolume if FS supports it) |
| `environmentFile` | `null` | Path to sops-rendered dotenv |
| `configFile` | `null` (uses generated) | Override path to `config.yaml` |
| `settings` | `{}` | Nix attrset → YAML, merged into default config |
| `soulFile` | `null` (uses bundled) | Override `SOUL.md` |
| `openBindAddress` | `0.0.0.0` | API server bind |
| `apiPort` | `8642` | API server port |
| `webhookPort` | `8644` | Webhook gateway port |
| `telegramAllowedUsers` | `[]` | Whitelist user IDs |
| `openaiBaseUrl` | `https://litellm.homelab.pastelariadev.com/v1` | LiteLLM proxy |
| `memoryMax` | `2G` | systemd `MemoryMax` |
| `cpuQuota` | `200%` | systemd `CPUQuota` |
| `openFirewall` | `false` | Open apiPort + webhookPort |

## sops-nix integration

Required env keys (filename of the secret matters less than these key names inside it — upstream hermes reads them directly):

    LITELLM_API_KEY=...
    OPENAI_API_KEY=...                       # same as LITELLM_API_KEY
    OPENROUTER_API_KEY=...
    API_SERVER_KEY=...                       # 48-char hex; required when binding 0.0.0.0
    HERMES_TELEGRAM_BOT_TOKEN=...            # renamed from TELEGRAM_BOT_TOKEN
    HERMES_DISCORD_BOT_TOKEN=...             # renamed from DISCORD_BOT_TOKEN
    EXA_API_KEY=...

The module bridges `HERMES_*_BOT_TOKEN` → the upstream-expected `TELEGRAM_BOT_TOKEN` / `DISCORD_BOT_TOKEN` at process start via the `ExecStart` wrapper. This avoids collision with the homelab Grafana / healthcheck notification stack which already uses unprefixed `TELEGRAM_BOT_TOKEN`.

### One-time secret seeding

    # define encrypted secrets
    sops secrets/hermes.env.sops
    # paste keys per above, save (sops auto-encrypts)

    # rebuild — secret lands at /run/secrets/hermes-agent
    sudo nixos-rebuild switch

## config.yaml

Built-in default tracks the user's battle-tested homelab config — LiteLLM proxy as model backend, `qwen-chat` default, 60-turn max, memory + wiki provider enabled, redact_pii on. Override piecemeal via `services.hermes-agent.settings`:

    services.hermes-agent.settings = {
      model.default = "claude-opus-4-7";
      agent.max_turns = 120;
      memory.nudge_interval = 5;
    };

Or replace wholesale with a literal file:

    services.hermes-agent.configFile = ./config.yaml;

Runtime values for `model.api_key`, `${OPENAI_API_KEY}`, etc come from `EnvironmentFile`. The YAML retains the `${VAR}` syntax — upstream hermes interpolates at load time.

## SOUL.md

Personality contract. Bundled default reflects homelab operator role. Override:

    services.hermes-agent.soulFile = ./my-soul.md;

## Migration from Docker

Current state: hermes runs via `machines/discovery/hermes-agent.yml` on host Discovery. Migration steps to swap into the NixOS module:

1.  Stop the container

        ssh discovery 'sudo systemctl stop podman-compose-hermes-agent.service'
        # or: ssh discovery 'docker stop hermes-agent'

2.  Move data dir

        ssh discovery 'sudo mv /home/erik/homelab/apps/hermes-agent /var/lib/hermes-agent'
        ssh discovery 'sudo chown -R 10000:10000 /var/lib/hermes-agent'

    If `/var/lib` is on btrfs, convert the moved dir into a proper subvolume after the fact:

        sudo btrfs filesystem usage /var/lib | head        # confirm btrfs
        # (optional snapshot promotion handled by the bootstrap on next start)

3.  Add the module + sops secret to Discovery's NixOS config (see [example/configuration.nix](example/configuration.nix)).

4.  Switch

        sudo nixos-rebuild switch

5.  Update SWAG upstream

    `machines/discovery/config/swag/nginx/proxy-confs/hermes.subdomain.conf` currently targets the Docker container's DNS name `hermes-agent:8642`. Change to host:

        set $upstream_app 127.0.0.1;
        set $upstream_port 8642;
        set $upstream_proto http;

    Reload SWAG: `docker exec swag nginx -s reload`.

6.  Verify

        sudo systemctl status hermes-agent
        curl http://127.0.0.1:8642/health
        sudo journalctl -u hermes-agent -f

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
      telegramAllowedUsers = [ 7729797827 ];
    };

Full example at [example/discovery-container.nix](example/discovery-container.nix).

## Client setup (laptop / per-user)

See [docs/CLIENT.md](docs/CLIENT.md). Summary: each hermes install has its own brain. Recommended pattern is local CLI on laptop (separate brain, shared LiteLLM backend) + Telegram/Discord for homelab ops directed at Discovery.

## See also

- [docs/SOPS.md](docs/SOPS.md) — sops-nix integration recipe
- [docs/ISOLATION.md](docs/ISOLATION.md) — bare-metal vs container vs VM trade-offs
- [docs/CLIENT.md](docs/CLIENT.md) — laptop client patterns (A/B/C/D)
- [docs/UPSTREAM_PR.md](docs/UPSTREAM_PR.md) — plan for contributing back to NousResearch
- [example/configuration.nix](example/configuration.nix) — bare-metal NixOS host config
- [example/discovery-container.nix](example/discovery-container.nix) — nixos-container variant
