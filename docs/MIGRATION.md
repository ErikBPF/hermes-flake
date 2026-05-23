# Migration from Docker

The upstream NousResearch ships hermes-agent as a Docker image. If you've been running it that way and want to switch to the NixOS module, here's the safe migration path.

## Inventory before you migrate

| Where | What |
|---|---|
| Docker volume / bind mount (e.g. `/path/to/apps/hermes-agent`) | Persistent state — sessions, skills, wiki, kanban.db, state.db, memories |
| `.env` file referenced by `docker-compose.yml` | Secrets — bot tokens, API keys |
| `config.yaml` in the mount | Optionally edited from upstream defaults |
| `SOUL.md` in the mount | Persona override (if you customized) |

## Plan

1. Stop the container.
2. Move the data dir to where the NixOS service expects it.
3. Set ownership to UID/GID 10000 (matches the service user).
4. Move secrets into your secret store (sops-nix, age, agenix, …) and reference via `services.hermes-agent.environmentFile`.
5. (Optional) Capture your existing `config.yaml` as `services.hermes-agent.settings` for declarative reproduction.
6. (Optional) Capture your existing `SOUL.md` as a path passed to `services.hermes-agent.soulFile`.
7. Add the module + secret to your NixOS config (see [`example/configuration.nix`](../example/configuration.nix)).
8. `nixos-rebuild switch`.
9. Update any reverse proxy (SWAG, Caddy, nginx) to point at `127.0.0.1:8642` since the service binds the host now.
10. Verify.

## Commands

```bash
# 1. stop the container
ssh hostname 'sudo systemctl stop podman-compose-hermes-agent.service'
# or: docker stop hermes-agent

# 2. move dir
ssh hostname 'sudo mv /old/path/hermes-agent /var/lib/hermes-agent'

# 3. chown to service UID/GID (matches the migrated Docker UID 10000)
ssh hostname 'sudo chown -R 10000:10000 /var/lib/hermes-agent'

# (optional) if /var/lib is on btrfs, snapshot before continuing
ssh hostname 'sudo btrfs subvolume snapshot /var/lib/hermes-agent /var/lib/snapshots/hermes-pre-nixos'

# 4. move secrets to sops — see docs/SOPS.md for the recipe.

# 5. capture config.yaml into NixOS:
#    nix-instantiate --eval -E '(import <nixpkgs/lib>).fromYAML (builtins.readFile ./config.yaml)'
#    paste the attrset into services.hermes-agent.settings = {...};
#
# (Or just point services.hermes-agent.configFile at the path directly to skip the conversion.)

# 6. capture SOUL.md:
#    services.hermes-agent.soulFile = ./SOUL.md;
#    (file gets copied into the nix store and bind-mounted into the runtime dir)

# 7-8. apply
ssh hostname 'sudo nixos-rebuild switch --flake .#hostname'

# 9. update reverse proxy upstream to 127.0.0.1:8642 (the host binds now,
#    not the container DNS name).

# 10. verify
ssh hostname 'sudo systemctl status hermes-agent'
ssh hostname 'curl http://127.0.0.1:8642/health'
ssh hostname 'sudo journalctl -u hermes-agent -f'
```

## If something goes wrong

The original Docker volume is still on disk (you moved it, didn't delete). Rollback:

```bash
ssh hostname 'sudo systemctl stop hermes-agent'
ssh hostname 'sudo mv /var/lib/hermes-agent /old/path/hermes-agent'
ssh hostname 'sudo systemctl start podman-compose-hermes-agent'
```

Restore the reverse proxy upstream to the container's DNS name and you're back where you started.

## Snapshots

`/var/lib/hermes-agent` is a btrfs subvolume after bootstrap. Daily snapshots:

```bash
sudo btrfs subvolume snapshot -r /var/lib/hermes-agent \
    /var/lib/snapshots/hermes-$(date +%Y%m%d-%H%M)
```

Offsite via `btrfs send | ssh remote 'btrfs receive ...'`.

## What persists across the migration

See [`docs/STATE.md`](STATE.md) for the full list. Short version: everything important (sessions, skills, wiki, kanban.db, state.db, memories) is preserved by step 2. Caches and lazy-installed binaries (`bin/`, `cache/`, `audio_cache/`, etc.) are regenerated on first start.
