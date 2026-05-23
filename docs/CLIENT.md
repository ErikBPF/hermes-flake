# Client Setup (Laptop / Per-User)

Hermes has no single-brain-shared-across-machines model. Each install has its own memory + skills. Three patterns for using a remote hermes (Discovery) from a laptop:

## Pattern A — Local CLI, shared LiteLLM backend (recommended)

Laptop runs its own `hermes` CLI for local terminal work. Shares the LiteLLM endpoint with Discovery so model usage is centralized. Memory stays local to the laptop.

```nix
# In your home-manager config:
imports = [ hermes-flake.homeManagerModules.default ];

programs.hermes-agent = {
  enable = true;
  dataDir = "${config.xdg.dataHome}/hermes";  # own memory
  secrets = {
    openaiApiKeyFile = config.sops.secrets."hermes-client/openai".path;
    anthropicApiKeyFile = config.sops.secrets."hermes-client/anthropic".path;
  };
  extraEnvironment = {
    OPENAI_BASE_URL = "https://litellm.homelab.pastelariadev.com/v1";
    HERMES_DEFAULT_MODEL = "qwen-chat";
  };
};
```

When to use: ad-hoc local tasks, no need to share state with Discovery.

## Pattern B — Web dashboard (no install)

Discovery's API server is exposed via SWAG. Open in browser:

    https://hermes.<your-domain>/

Auth: `API_SERVER_KEY` header.

Pros: zero client setup; works on phone/iPad.
Cons: no terminal integration; no local file access.

## Pattern C — Telegram / Discord

The Discovery hermes is wired to Telegram (Romozinha bot) and Discord (Romozinha#4758). Both work from anywhere with internet.

Most natural for: status checks, quick queries, "deploy X", "what's running on Orion".

No client setup needed. The Discovery service handles auth via `TELEGRAM_ALLOWED_USERS` whitelist.

## Pattern D — ACP bridge (advanced, IDE integration)

`hermes-acp` exposes hermes as an Agent Control Protocol stdio server. Plug into Zed, Cursor, Claude Code, or any ACP-compatible client.

```fish
# Local laptop hermes, ACP mode for the IDE
hermes-acp --setup
# Edit ~/.hermes/config.yaml — confirm provider/model
# IDE config: add stdio agent:
#   command: hermes-acp
```

This still runs hermes LOCALLY (your laptop is the executor). To execute remotely against Discovery's hermes, use Pattern B (web API) from the IDE — most IDEs support OpenAI-compatible endpoints, and Discovery's API server is one.

## Recommendation

Use **A** (local CLI) + **C** (Telegram for homelab ops) together:

- Terminal work, project-scoped tasks → laptop hermes CLI (Pattern A)
- "Restart hermes on discovery", "what's syncthing doing", quick lookups → Telegram message to Romozinha (Pattern C)
- Phone access → Telegram (Pattern C) or web dashboard (Pattern B)

## Migration from existing `~/.hermes/`

If your laptop already has a hand-rolled `~/.hermes/` from a `uv tool install` era, the nix-managed HM module respects it as `$HERMES_HOME`. You can keep it OR migrate to the module's `dataDir`:

```fish
# Keep existing
programs.hermes-agent.dataDir = "/home/erik/.hermes";

# OR migrate to XDG location
mv ~/.hermes "$XDG_DATA_HOME/hermes"
# (module default already points at $XDG_DATA_HOME/hermes)
```

Then clean up the stale uv-installed binary:

```fish
uv tool uninstall hermes-agent
# Now `which hermes` resolves to ~/.nix-profile/bin/hermes
```
