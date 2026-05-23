# State Files & Migration

What lives in `dataDir` (= `HERMES_HOME`) — and what's worth preserving when migrating between hosts or restoring from backup.

## Contents of `dataDir`

| Path | Owner | Purpose | Preserve? | Notes |
|---|---|---|---|---|
| `config.yaml` | nix | Generated from `services.hermes-agent.settings` | No | rebuild rewrites it |
| `SOUL.md` | nix | Personality file | No | rebuild rewrites it |
| `.env` | (deprecated) | Pre-sops local secrets | Delete after sops kicks in | secrets now in `EnvironmentFile=` |
| `state.db` | hermes | Main runtime state (sessions, conversations, prefs) | **Yes** | sqlite, 1-5 MB typical |
| `state.db-shm` / `state.db-wal` | hermes | SQLite write-ahead log | No | regenerated |
| `kanban.db` | hermes | Kanban board state | **Yes** | sqlite, ~100 KB |
| `response_store.db` | hermes | Response cache | Yes (optional) | regenerated on miss |
| `sessions/` | hermes | Past conversation history | **Yes** | per-session JSON |
| `memories/` | hermes | Long-term memory entries | **Yes** | wiki provider stores under `wiki/` instead |
| `wiki/` | hermes | Karpathy-style knowledge wiki | **Yes** | markdown notes |
| `skills/` | hermes | Learned skills (markdown + Python) | **Yes** | grows over time, often largest dir |
| `cron/` | hermes | Scheduled tasks | **Yes** | usually empty |
| `hooks/` | hermes | User hooks | **Yes** | usually empty |
| `platforms/` | hermes | Per-platform state | Yes | small |
| `pairing/` | hermes | Device pairing tokens | Yes | small |
| `cache/` | hermes | Generic cache | No | regenerated |
| `audio_cache/` | hermes | STT/TTS audio buffers | No | regenerated |
| `image_cache/` | hermes | Vision tool images | No | regenerated |
| `logs/` | hermes | Runtime logs | No | rotates |
| `lsp/` | hermes | LSP server caches | No | regenerated |
| `sandboxes/` | hermes | Tool sandboxes | No | ephemeral |
| `bin/` | hermes | Lazy-installed CLIs (ripgrep, ffmpeg, node) | No | re-fetched |
| `channel_directory.json` | hermes | Discord/Telegram channel map | Yes | tied to gateway state |
| `gateway_state.json` | hermes | Gateway restart state | Yes | small |
| `models_dev_cache.json` | hermes | models.dev cache | No | regenerated |
| `ollama_cloud_models_cache.json` | hermes | Ollama cloud list | No | regenerated |
| `.skills_prompt_snapshot.json` | hermes | Last skills prompt | No | regenerated |
| `.restart_*` | hermes | Restart bookkeeping | No | regenerated |
| `.update_check` | hermes | Update check timestamp | No | regenerated |
| `feishu_seen_message_ids.json` | hermes | Feishu dedup | Yes | only if you use Feishu |
| `interrupt_debug.log` | hermes | Debug log | No | rotates |

## Minimal backup set

If you only want the irreplaceable bits:

```fish
tar czf hermes-backup-$(date +%Y%m%d).tar.gz \
  -C /var/lib/hermes-agent \
  state.db kanban.db sessions memories wiki skills cron hooks platforms pairing \
  channel_directory.json gateway_state.json
```

## Snapshot via btrfs

`dataDir` lives on a btrfs subvolume (created by the bootstrap). Atomic snapshot:

```fish
sudo btrfs subvolume snapshot -r /var/lib/hermes-agent /var/lib/snapshots/hermes-$(date +%Y%m%d-%H%M)
```

Send/receive to an offsite host (e.g. over Tailscale):

```fish
sudo btrfs send /var/lib/snapshots/hermes-20260523-1400 | \
  ssh voyager 'sudo btrfs receive /backup/hermes/'
```

## Migration: Docker → NixOS

See [`docs/MIGRATION.md`](MIGRATION.md) for the step-by-step Docker → NixOS procedure. All state (sessions, skills, wiki, kanban, memories) is preserved by moving the host-side data dir.

## Per-user dataDir (home-manager)

If you previously ran hermes from `pip install` or `uv tool install`, your state is in `~/.hermes/` by default. Point the HM module at it:

```nix
programs.hermes-agent.dataDir = "/home/me/.hermes";
```

Or migrate to XDG:

```bash
mv ~/.hermes "$XDG_DATA_HOME/hermes"
```

Once `services.hermes-agent.environmentFile` or `programs.hermes-agent.secrets.*` are wired to a secret store, the standalone `~/.hermes/.env` plaintext file is redundant and can be removed.
