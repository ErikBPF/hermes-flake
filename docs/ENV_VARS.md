# Environment Variable Reference

Audited against upstream `gateway/config.py`, `gateway/platforms/{api_server,webhook,telegram}.py`, `hermes_cli/{config,setup,webhook}.py`, and `docker/entrypoint.sh` at hermes-agent `v2026.5.16`.

Three buckets: ones the flake exposes as module options (declarative), ones that must come from the sops `EnvironmentFile` (secrets), and ones you can set ad-hoc via `services.hermes-agent.extraEnvironment`-style overrides.

## Module-managed (declarative)

| Env var | Module option | Default |
|---|---|---|
| `HERMES_HOME` | `dataDir` | `/var/lib/hermes-agent` |
| `HERMES_CONFIG_FILE` | computed from `configFile` / `dataDir` | `${dataDir}/config.yaml` |
| `HERMES_SOUL_FILE` | computed from `soulFile` / `dataDir` | `${dataDir}/SOUL.md` |
| `HERMES_MAX_ITERATIONS` | `maxIterations` | `90` |
| `HERMES_PROFILE` | `profile` | unset |
| `HERMES_DASHBOARD` | `enableDashboard` | `0` (unset) |
| `HERMES_DASHBOARD_HOST` | `dashboardHost` | `127.0.0.1` |
| `HERMES_DASHBOARD_PORT` | `dashboardPort` | `9119` |
| `API_SERVER_ENABLED` | hardcoded `true` | `true` |
| `API_SERVER_HOST` | `openBindAddress` | `0.0.0.0` |
| `API_SERVER_PORT` | `apiPort` | `8642` |
| `API_SERVER_CORS_ORIGINS` | `apiServerCorsOrigins` (list joined `,`) | unset |
| `API_SERVER_MODEL_NAME` | `apiServerModelName` | unset |
| `WEBHOOK_ENABLED` | hardcoded `true` | `true` |
| `WEBHOOK_PORT` | `webhookPort` | `8644` |
| `TELEGRAM_ALLOWED_USERS` | `telegramAllowedUsers` (list joined `,`) | unset |
| `TELEGRAM_ALLOWED_CHATS` | `telegramAllowedChats` (list joined `,`) | unset |
| `TELEGRAM_ALLOWED_TOPICS` | `telegramAllowedTopics` (list joined `,`) | unset |
| `OPENAI_BASE_URL` | `openaiBaseUrl` | `https://litellm.homelab.pastelariadev.com/v1` |

## Sops EnvironmentFile (secrets)

Define these inside the `hermes_server.env` block in `secrets.yaml`. The systemd unit reads them via `EnvironmentFile=`.

| Env var | Required | Purpose |
|---|---|---|
| `LITELLM_API_KEY` | yes | LiteLLM proxy auth (set this even when you use OpenAI/Anthropic upstream because hermes' default config references it) |
| `OPENAI_API_KEY` | yes | Hermes core model auth — typically `= ${LITELLM_API_KEY}` |
| `OPENROUTER_API_KEY` | recommended | Provider fallback |
| `API_SERVER_KEY` | required when `openBindAddress != 127.0.0.1` | 48-char hex bearer for API server |
| `WEBHOOK_SECRET` | recommended | Global webhook HMAC fallback (used when a route omits its own) |
| `WEBHOOK_<ROUTE>_SECRET` | per-route | HMAC for each named route (see `docs/WEBHOOK_ROUTES.md`) |
| `HERMES_TELEGRAM_BOT_TOKEN` | yes (if telegram) | Token from BotFather — bridged → `TELEGRAM_BOT_TOKEN` at exec to avoid collision with homelab notification stack |
| `HERMES_DISCORD_BOT_TOKEN` | yes (if discord) | Same pattern → `DISCORD_BOT_TOKEN` |
| `EXA_API_KEY` | optional | Exa search tool |
| `ANTHROPIC_API_KEY` | optional | Direct Anthropic provider |
| `FIRECRAWL_API_KEY` | optional | Firecrawl tool |
| `PARALLEL_API_KEY` | optional | Parallel search backend |
| `FAL_API_KEY` | optional | FAL image gen |
| `BROWSERBASE_API_KEY` | optional | Browser automation backend |

## extraEnvironment escape hatch

Anything not modeled by an option above can be set via `services.hermes-agent.extraEnvironment = { FOO = "bar"; };` — included in the unit's `Environment=`. Useful for:

| Env var | Purpose |
|---|---|
| `HERMES_LANGUAGE` | Locale code (`en`, `pt-BR`, etc.) |
| `HERMES_QUIET` | `1` to suppress non-essential log output |
| `HERMES_DEV` | `1` to enable dev flags (verbose errors, stack traces) |
| `HERMES_ACCEPT_HOOKS` | `1` to auto-accept hook prompts |
| `HERMES_GATEWAY_BUSY_ACK_ENABLED` | toggle busy-ack messages |
| `HERMES_OPENROUTER_CACHE` | OpenRouter response cache path |
| `HERMES_OPENROUTER_CACHE_TTL` | cache TTL seconds |
| `HERMES_KANBAN_*` | kanban subsystem config (board path, claim TTL, etc.) |
| `HERMES_TERMINAL_SECURITY_MODE` | terminal tool sandbox mode |
| `HERMES_AUTO_CONTINUE_FRESHNESS` | auto-resume window |

Full grep of upstream `os.environ.get` calls produces ~50 `HERMES_*` vars; only the production-relevant ones are listed above. Search `gateway/` and `hermes_cli/` if you need a niche one.

## Things that are NOT env vars (config.yaml-only)

| Subject | Where it lives |
|---|---|
| Telegram `reply_to_mode`, `guest_mode`, `disable_link_previews` | `platforms.telegram.{reply_to_mode, guest_mode, extra.disable_link_previews}` |
| Discord `require_mention`, `auto_thread`, `reactions` | TOP-LEVEL `discord.{...}` (NOT `platforms.discord`) |
| Webhook routes + prompts | `platforms.webhook.extra.routes.<name>.{prompt, hmac_secret_env, deliver_only, ...}` |
| Agent `max_turns`, `verbose`, `reasoning_effort` | `agent.{max_turns, verbose, reasoning_effort}` |
| Memory `nudge_interval`, `flush_min_turns` | `memory.{nudge_interval, flush_min_turns}` |
| Compression `threshold`, `target_ratio` | `compression.{threshold, target_ratio}` |
| Tool guardrails | `tool_loop_guardrails.{...}` |
| Skills creation prompt cadence | `skills.creation_nudge_interval` |

All of these go through `services.hermes-agent.settings.<path>`. The flake's default config (`config.yaml.nix`) sets the homelab-tuned values; override piecemeal.

## Env vs config.yaml precedence

When both are set, **env wins** (gateway/config.py merges env into config at runtime). This means:

- `WEBHOOK_PORT` env overrides `platforms.webhook.extra.port` in YAML
- `TELEGRAM_ALLOWED_USERS` env overrides `platforms.telegram.allowed_users` in YAML
- `API_SERVER_PORT` env overrides nothing in YAML (no YAML field for it)

For the homelab deployment, declarative env (from module options) is the canonical source. Don't hand-edit `config.yaml` for these — change `services.hermes-agent.*` and rebuild.
