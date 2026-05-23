# Webhook Routes

Webhook routes are defined ONLY in `config.yaml` — env vars cannot create them. The flake's `settings` option lets you declare routes inline; per-route secrets come from sops.

## Schema

Each route lives under `platforms.webhook.extra.routes.<name>`:

```yaml
platforms:
  webhook:
    enabled: true
    extra:
      routes:
        github-ci:
          # Required: HMAC secret, referenced by env var name (not literal value)
          hmac_secret_env: WEBHOOK_GITHUB_CI_SECRET
          # Required: prompt template (Jinja2) — formatted with the payload
          prompt: |
            GitHub CI event from {{ payload.repository.full_name }}:
            {{ payload.action }} on {{ payload.workflow_run.name }}
            status={{ payload.workflow_run.conclusion }}
            URL: {{ payload.workflow_run.html_url }}
          # Optional: silently store payload, don't trigger agent (default false)
          deliver_only: false
          # Optional: filter — only fire when this Jinja expression evals truthy
          # condition: '{{ payload.action == "completed" }}'

        linear-incident:
          hmac_secret_env: WEBHOOK_LINEAR_INCIDENT_SECRET
          prompt: |
            Linear incident: {{ payload.data.title }} ({{ payload.data.priority }})
```

The route name becomes the URL path: `POST /webhooks/github-ci` on `apiPort`.

## Declaring in Nix

```nix
services.hermes-agent.settings.platforms.webhook.extra.routes = {
  github-ci = {
    hmac_secret_env = "WEBHOOK_GITHUB_CI_SECRET";
    prompt = ''
      GitHub CI event: {{ payload.action }}
      Repo: {{ payload.repository.full_name }}
    '';
    deliver_only = false;
  };

  linear-incident = {
    hmac_secret_env = "WEBHOOK_LINEAR_INCIDENT_SECRET";
    prompt = "Linear: {{ payload.data.title }}";
  };
};
```

## Sops secrets — per-route

Each `hmac_secret_env` value must be a real env var in the EnvironmentFile. Add to `hermes_server.env` in `secrets.yaml`:

```
WEBHOOK_SECRET=<global-fallback-hmac>
WEBHOOK_GITHUB_CI_SECRET=<random-32-bytes-hex>
WEBHOOK_LINEAR_INCIDENT_SECRET=<random-32-bytes-hex>
```

Generate a secret:

```fish
openssl rand -hex 32
```

## Verifying

```fish
# on the host running hermes — confirm route registered
ssh discovery 'sudo journalctl -M hermes -u hermes-agent --since "5 min ago" | grep webhook'
# expect: [webhook] Listening on 0.0.0.0:8644 — routes: github-ci, linear-incident

# Trigger from your laptop
sig=$(echo -n "$payload" | openssl dgst -sha256 -hmac "$WEBHOOK_GITHUB_CI_SECRET" -hex | awk '{print $2}')
curl -X POST https://hermes.your-domain.com/webhooks/github-ci \
  -H "X-Hub-Signature-256: sha256=$sig" \
  -H "Content-Type: application/json" \
  -d "$payload"
```

## Anti-patterns

- Don't put a literal secret in `hmac_secret_env`. The string IS an env var name, not the secret itself.
- Don't reuse the same secret across routes — defeats the point of per-route scoping.
- Don't set `INSECURE_NO_AUTH` as the value (upstream allows it but warns loudly).
- Don't rely on the global `WEBHOOK_SECRET` for production routes — define a per-route secret explicitly.
