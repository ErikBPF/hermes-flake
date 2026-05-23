# Contributing

This flake is a third-party Nix wrapper around [`NousResearch/hermes-agent`](https://github.com/NousResearch/hermes-agent) — see [`NOTICE`](NOTICE) for attribution. The goal: track upstream cleanly while exposing a NixOS-native service module + isolation wrappers. PRs welcome.

## Where to report

| Symptom | Where |
|---|---|
| Hermes-agent crashes, weird LLM behavior, prompt issues, model selection | Upstream: [`NousResearch/hermes-agent`](https://github.com/NousResearch/hermes-agent/issues) |
| `nix build` fails / closure issues / Python dep build errors | This repo |
| NixOS module options / systemd unit / sops integration / container isolation | This repo |
| Hourly auto-update workflow opened a broken PR | This repo |
| Security vuln | [`SECURITY.md`](SECURITY.md) (private security advisory) |

## How updates land

| Source | Mechanism | Cadence |
|---|---|---|
| Upstream `hermes-agent` releases | Hourly cron in `.github/workflows/update-hermes-agent.yml` polls GitHub releases, opens auto-merge PR if a new tag exists | Every hour, on the hour |
| `nixpkgs` / `flake-parts` / `uv2nix` / `pyproject-nix` | Manual `nix flake update` | On demand or via Dependabot if added |
| C-extension overrides | Manual edit to `overrides.nix` when builds break | As needed |

Goal: new upstream `hermes-agent` releases are mirrored to a tag here within ~30 min.

## Manual local update

```bash
./scripts/update-version.sh           # bump to latest upstream release
./scripts/update-version.sh --check   # exit 1 if newer release exists
./scripts/update-version.sh --version v2026.5.16   # pin a specific tag
```

The script:
1. Reads current pin from `flake.nix` (`hermes-agent-src.url`)
2. Queries `https://api.github.com/repos/NousResearch/hermes-agent/releases/latest`
3. Patches the URL via `sed`
4. Runs `nix flake update hermes-agent-src`
5. Verifies `nix build .#hermes-agent` succeeds + runs the smoke check
6. Aborts (reverting flake files) if either fails

## Pinning model

| Ref | Behavior |
|-----|----------|
| `<commit-sha>` | Immutable |
| Semver tag like `v0.1.0` (when published) | Immutable |
| `main` | Tracks newest commit (preferred for end users wanting freshness) |

Tag releases are cut after a green run of all checks + manual review.

## Adding / changing module options

1. Add the option in `module.nix` with a clear `description` mapping to either an upstream env var or `config.yaml` path.
2. Update `docs/ENV_VARS.md` truth table.
3. Update the README options matrix.
4. Add a check exercising the new option in `checks.nix` (mirror the `module-full-options` pattern).
5. Run `nix flake check`.

## C-extension overrides

When a new release adds a Python dep with a native build, `nix build .#hermes-agent` will fail. Add an override in `overrides.nix`:

```nix
sounddevice = prev.sounddevice.overrideAttrs (old: {
  buildInputs = (old.buildInputs or []) ++ [pkgs.portaudio];
});
```

Document why the override exists with a one-line comment (the C lib it needs and why).

## Style

- `alejandra` formatting (`nix fmt` runs it).
- `statix` lint (`statix check .`) — no warnings on changed files.
- Conventional Commits in the subject line. Body explains *why* not *what*.
- Module options follow nixpkgs naming conventions (`mkOption`, `mkEnableOption`, `cfg`).
- Comments explain WHY (constraints, gotchas) not WHAT.

## Testing

```bash
nix flake check                                       # eval everything
nix build .#hermes-agent                              # base build
nix build .#checks.x86_64-linux.smoke                 # individual checks
nix build .#checks.x86_64-linux.nixos-module          # VM test (needs KVM)
```

See [README.md § Tests](README.md#tests).

## Reporting issues

- **Build failure on a new release**: file an issue with `nix build .#hermes-agent --print-build-logs` output. If a C-ext dep is missing, suggest the `overrides.nix` patch.
- **Schema drift**: if `docs/ENV_VARS.md` claims a var that upstream removed, file an issue tagged `schema`.
- **Container regression**: VM test (`checks.<system>.nixos-module`) catches most. If something slips, reproduce with `nix build .#checks.<system>.nixos-module --print-build-logs`.

## Releasing a tag

```bash
git tag v0.X.Y -m "Release v0.X.Y — tracking hermes-agent v2026.X.Y"
git push origin v0.X.Y
```

CI will build the tagged ref; downstream users pinning to the tag get the same store paths.

## Publishing a release (maintainer flow)

See [`docs/RELEASING.md`](docs/RELEASING.md) — versioning model, tag flow, hotfix, rollback.

After cutting a release, post in:

- [NixOS Discourse → Announcements](https://discourse.nixos.org/c/announcements/8) — title `hermes-flake v0.X.Y — third-party Nix flake for NousResearch/hermes-agent`. Link the repo + the `docs/ISOLATION.md` trade-off matrix.
- [`r/NixOS`](https://reddit.com/r/NixOS) — link post to the Discourse thread (centralize traffic).
- NixOS Discord `#announcements`.
- (Optional) `NousResearch/hermes-agent` discussions or issues — ask whether they want a `Nix users` line in their README.

Then submit to community indexes:

- [`nix-community/awesome-nix`](https://github.com/nix-community/awesome-nix) — PR adding the flake under `Modules → AI`.
- [NixOS Wiki](https://wiki.nixos.org) — create `Hermes Agent` page with install snippets + link back to this repo's docs.
- [FlakeHub](https://flakehub.com) — claim the flake for a stable URL + free public binary cache.
- (Optional) [`nix-community/flake-registry`](https://github.com/nix-community/flake-registry) — PR adding `hermes-flake` shorthand.

Repo settings to maintain discoverability:

- **Topics** (under `About`): `nix`, `nix-flake`, `nixos`, `nixos-module`, `hermes-agent`, `nousresearch`, `llm`, `ai-agent`, `anthropic`, `sops-nix`, `microvm`, `nspawn`, `podman`, `systemd`
- **Description**: copy of `flake.nix`'s `description`
- **Social preview image**: 1280×640 PNG with logo + tagline (Settings → Social preview)
- **Discussions**: enabled for Q&A

## License

MIT — matches upstream's MIT license. Contributions are accepted under the same license. Submitting a PR means you agree your contribution may be relicensed under any OSI-approved license that's compatible with MIT, should upstream re-license.
