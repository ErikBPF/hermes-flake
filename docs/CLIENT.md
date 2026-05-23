# Client Patterns

Hermes has no shared-brain-across-machines model. Each install owns its own memory + skills. Four common patterns for using a remote hermes deployment from a workstation:

## Pattern A — Local CLI, shared model backend

The workstation runs its own `hermes` CLI for local terminal work. Shares the model endpoint (e.g. a LiteLLM proxy) with the remote service so model usage is centralized. Memory stays local to the workstation.

```nix
imports = [ hermes-flake.homeManagerModules.default ];

programs.hermes-agent = {
  enable = true;
  dataDir = "${config.xdg.dataHome}/hermes";
  secrets = {
    openaiApiKeyFile = config.sops.secrets."hermes-client/openai".path;
    anthropicApiKeyFile = config.sops.secrets."hermes-client/anthropic".path;
  };
  extraEnvironment = {
    OPENAI_BASE_URL = "https://api.openai.com/v1";  # or your LiteLLM proxy
    HERMES_DEFAULT_MODEL = "claude-opus-4-7";
  };
};
```

When to use: ad-hoc local tasks; no need to share state with a remote brain.

## Pattern B — Local CLI delegating to a remote API gateway

Make the workstation's CLI a thin client over the remote service's API server. `OPENAI_BASE_URL` points at the remote, `OPENAI_API_KEY` = remote's `API_SERVER_KEY`. Every chat request flows through the remote hermes process, which then calls upstream models.

```nix
programs.hermes-agent.extraEnvironment = {
  OPENAI_BASE_URL = "https://hermes.example.com/v1";
};
programs.hermes-agent.secrets.openaiApiKeyFile =
  config.sops.secrets."hermes-client/api_key".path;
```

The remote `API_SERVER_KEY` is the bearer; the client's `OPENAI_API_KEY` env var carries it. Chain: local CLI → remote hermes API → upstream provider.

## Pattern C — Web dashboard (no client install)

The remote service exposes an OpenAI-compatible endpoint on its API port (default 8642). Point any compatible client at it:

- [Open WebUI](https://github.com/open-webui/open-webui)
- [LibreChat](https://github.com/danny-avila/LibreChat)
- Built-in hermes dashboard (when `services.hermes-agent.enableDashboard = true`)

```
URL:    https://hermes.example.com/v1
Bearer: <API_SERVER_KEY>
```

Best for phone/iPad access.

## Pattern D — Telegram / Discord / Slack

The remote hermes-agent service has gateway adapters for messaging platforms. Once configured (bot tokens in the `EnvironmentFile`, `TELEGRAM_ALLOWED_USERS` set), users just send DMs / @-mentions.

Best for: quick remote queries from anywhere; phone-friendly; no client install.

## Pattern E — ACP bridge (IDE integration)

`hermes-acp` exposes hermes as an [Agent Control Protocol](https://github.com/Agent-Control-Protocol/) stdio server. Plug into Zed, Cursor, Claude Code, or any ACP-compatible IDE.

```bash
hermes-acp --setup
# IDE config — add stdio agent:
#   command: hermes-acp
```

This runs hermes locally on the workstation. To delegate execution to a remote hermes, use Pattern B from the IDE — most IDEs accept OpenAI-compatible endpoints, and the remote API server is one.

## Recommendation

Mix patterns by use case:

- Terminal work, project-scoped tasks → **A** (local CLI with own brain) or **B** (delegate to remote)
- Quick remote queries from anywhere → **D** (Telegram/Discord)
- Phone access → **C** (web dashboard) or **D** (Telegram)
- IDE-embedded coding agent → **E** (ACP)

## Migration from `pip install` / `uv tool install`

If you already have a hand-rolled `~/.hermes/` on a workstation, the HM module respects it as `$HERMES_HOME`:

```nix
programs.hermes-agent.dataDir = "/home/me/.hermes";
```

Or move to the XDG default:

```bash
mv ~/.hermes "$XDG_DATA_HOME/hermes"
# (module default already points at $XDG_DATA_HOME/hermes)
```

Then clean up the standalone CLI install:

```bash
uv tool uninstall hermes-agent
# now `which hermes` resolves to ~/.nix-profile/bin/hermes
```
