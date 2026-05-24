# Releasing

How to cut a tagged release of `hermes-flake`.

## When to tag

- After a noteworthy bump of the upstream `hermes-agent` pin (semver-significant from the user's perspective).
- After a meaningful module schema change (new options, default flips, removed options).
- After a security-relevant fix.
- Not for every trivial upstream bump — those land as `main` commits and consumers tracking `main` pick them up automatically.

## Versioning

Independent semver from upstream. `MAJOR.MINOR.PATCH`:

- `MAJOR` — breaking module-schema change (option removed/renamed, behavior flip that requires user action).
- `MINOR` — new option, new variant, new test, additive feature.
- `PATCH` — bug fix, doc improvement, dependency bump.

Track the upstream version per-tag in `CHANGELOG.md` so consumers can match.

## Pre-release checklist

```bash
# 1. ensure main is green
git checkout main
git pull
nix flake check

# 2. local sanity build
nix build .#hermes-agent
./result/bin/hermes --version

# 3. update CHANGELOG.md — move "Unreleased" entries under the new version heading
$EDITOR CHANGELOG.md

# 4. commit
git add CHANGELOG.md
git commit -m "chore: release v0.X.Y"

# 5. tag — annotated, signed if you have a key
git tag -a v0.X.Y -m "Release v0.X.Y — tracking hermes-agent vYYYY.M.D"
# Or signed:
# git tag -s v0.X.Y -m "Release v0.X.Y"

# 6. push
git push origin main --follow-tags
```

## What CI does on tag push

The `build` workflow runs on every push to a tag matching `v*` (matrix: linux/x86, linux/aarch64). magic-nix-cache serves the resulting store paths for downstream `nix run github:ErikBPF/hermes-flake/v0.X.Y` consumers.

## Cutting GitHub Release notes

After the tag is pushed:

```bash
gh release create v0.X.Y --notes-file <(awk '/^## v0.X.Y/,/^## v/' CHANGELOG.md | head -n -1)
```

Or via the GitHub web UI: paste the CHANGELOG section for the new tag.

## Post-release

- Update `README.md` "Versions" table with the new entry.
- Open a tracking issue for the next minor's roadmap.
- If upstream has cut new releases since the tag, the hourly auto-update workflow will eventually open a follow-up bump PR for `main` — no manual action needed.

## Hotfix flow

For a critical fix on the latest tag without bumping the upstream pin:

```bash
git checkout -b hotfix/v0.X.(Y+1) v0.X.Y
# apply fix
git commit -m "fix: <description>"
git tag -a v0.X.(Y+1) -m "Hotfix v0.X.(Y+1)"
git push origin hotfix/v0.X.(Y+1) --follow-tags
# open PR to main to forward-port the fix
```

## Rollback

If a tag turns out to be broken:

1. **Don't delete the tag** — downstream may already have it pinned. Forcing the ref to a different commit is destructive.
2. Cut `v0.X.(Y+1)` with the fix.
3. Update `README.md` "Versions" + `CHANGELOG.md` noting the bad tag.
4. Optionally: `gh release edit v0.X.Y --notes "⚠️ Known bad — use v0.X.(Y+1)"`.

## Yanking a release from the auto-update PR cron

If the cron tries to bump `hermes-agent` to a known-broken upstream tag, manually pin in `flake.nix` and push:

```nix
hermes-agent-src.url = "github:NousResearch/hermes-agent/v2026.M.D-1";  # previous tag
```

The hourly cron's `update-version.sh --check` will keep flagging the newer upstream tag as available; ignore the auto-PR until the upstream fix lands.
