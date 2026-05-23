# sops-nix Integration

`programs.hermes-agent.secrets.*ApiKeyFile` accepts paths to files containing single-line secret values. Render those via `sops-nix`.

## Setup

### 1. Define secrets in `secrets/hermes.yaml`

```yaml
# Encrypted with sops + age
anthropic: sk-ant-...
openai: sk-...
openrouter: sk-or-...
exa: ...
firecrawl: fc-...
```

### 2. Wire `sops-nix` to decrypt them at activation

```nix
# In your nixos config:
sops = {
  defaultSopsFile = ./secrets/hermes.yaml;
  age.keyFile = "/var/lib/sops-nix/key.txt";

  secrets = {
    "anthropic" = {
      owner = "hermes";
      mode = "0400";
      path = "/run/secrets/hermes/anthropic";
    };
    "openai" = {
      owner = "hermes";
      mode = "0400";
      path = "/run/secrets/hermes/openai";
    };
    "openrouter" = {
      owner = "hermes";
      mode = "0400";
      path = "/run/secrets/hermes/openrouter";
    };
    "exa" = {
      owner = "hermes";
      mode = "0400";
      path = "/run/secrets/hermes/exa";
    };
  };
};
```

### 3. Point hermes-agent at the rendered paths

```nix
# In your home-manager config:
programs.hermes-agent = {
  enable = true;
  secrets = {
    anthropicApiKeyFile = "/run/secrets/hermes/anthropic";
    openaiApiKeyFile = "/run/secrets/hermes/openai";
    openrouterApiKeyFile = "/run/secrets/hermes/openrouter";
    extraKeyFiles = {
      EXA_API_KEY = "/run/secrets/hermes/exa";
    };
  };
};
```

## How it works

The home-manager module injects into `bash.initExtra` / `fish.shellInit`:

```fish
test -r "/run/secrets/hermes/anthropic"; and set -gx ANTHROPIC_API_KEY (cat "/run/secrets/hermes/anthropic")
```

So every new shell auto-loads the secrets from disk. The secret values never appear in the nix store — only the *paths* do.

If using the systemd service (`systemdService.enable = true`), the service unit reads `Environment=` from the same paths via shell expansion — secrets stay on disk.

## Encrypting a new key

```fish
nix-shell -p sops age
echo "sk-newkey" | sops encrypt --input-type binary --output-type yaml /dev/stdin >> secrets/hermes.yaml
# Or interactively:
sops secrets/hermes.yaml
```

## Rotating a key

1. Edit secrets file: `sops secrets/hermes.yaml`
2. Replace value, save
3. Rebuild: `nixos-rebuild switch` — new key lands at `/run/secrets/hermes/<name>`
4. Restart shell or `source ~/.config/fish/config.fish` to pick up
5. Restart `systemctl --user restart hermes-agent.service` if running as service

## Alternative — direct env (no sops)

If you don't want sops, point the key files at plain files outside the repo:

```nix
programs.hermes-agent.secrets.anthropicApiKeyFile = "/var/lib/hermes-agent-secrets/anthropic";
```

Then `echo "sk-ant-..." > ~/.secrets/anthropic && chmod 600 ~/.secrets/anthropic`. Less safe, no encryption-at-rest in your dotfiles repo, but simplest.
