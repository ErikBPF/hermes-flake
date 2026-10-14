# Hermes release updater and package — leaf delivery checkpoint

**Stage / revision:** PR CI failure diagnosed; candidate 1 pending independent RV / 8
**Outcome:** native leaf checks remain GREEN; both protected architecture builds
failed desktop npm configuration. Shared npm adapter repair has local regression
GREEN; bounded local desktop build timed out during dependency fetch. Neither
architecture CI is GREEN, and actual desktop repair remains unverified.
**Human seed:** `lets do both. Also check our litellm health`
**Accepted scope:** stable release handling and upstream `v0.21.7`, from homelab
`docs/plans/2026-10-14-hermes-agent-delivery.md` and its linked delivery one-pager.
Main published [PR #59](https://github.com/ErikBPF/hermes-flake/pull/59).
This CI repair is uncommitted/unpublished; no merge, deployment or inference here.

## Current CI candidate

Verified checkout, PR and run head:
`2195d6af6e3b2df069c8bec838c6dbd2da060fe7`. Run `38583250103` failed
`build Hermes Desktop` on both
[x86](https://github.com/ErikBPF/hermes-flake/actions/runs/38583250103/job/115918386882)
and [ARM](https://github.com/ErikBPF/hermes-flake/actions/runs/38583250103/job/115918387470):
`npm error code EOVERRIDE`, direct `js-yaml` file URL conflicts with override.
These are observed source/build failures, not download infrastructure failures.

Root cause: `importNpmLock` rewrites direct dependencies to locked file URLs but
leaves override literal `4.3.1`. Candidate 1 changes only shared `lib.nix` adapter
to npm's [documented direct-spec reference](https://docs.npmjs.com/cli/v10/configuring-npm/package-json/#overrides),
`"js-yaml@^4": "$js-yaml"`. Exact upstream/lock version `4.3.1`, archive identity
and every other security override remain unchanged. No weaker npm flags or CI gates.

Receipts below are in `leaf-pr59-ci-MUNsA5/`, all mode `0600`:

- `run.json`, `x86-failed.log`, `arm-failed.log`: verified head and failed-step-only
  public logs; same error family on both architectures.
- `local-assert-red-G8QFgC.log`: actual adapter assertion fails before production
  repair, `npm direct js-yaml override must follow the rewritten locked dependency`.
  Initial `local-red.log` hit a test-only JSON string-context error, not RED;
  corrected metadata parsing discards context only in test assertions.
- `local-green-ZQDxBR.log`: adapter regression builds on x86 and evaluates on ARM;
  base/extras native identity and updater checks pass. This is not ARM runtime CI.
- `cached-regression-GZ4xRH.log`: npm regression, base/extras identity, updater,
  OCI/role-OCI, config/schema and existing lint all pass; accepted ref/revision
  unchanged. Existing masked statix/deadnix limits remain, not repaired here.
- `desktop-candidate1-ABwPMi.log`: job `sh_13ae7fe37001FbWdDgteoOkAjA` completed
  with timeout exit 124 after 480 seconds, still fetching npm archives. Renderer
  configuration was not reached; desktop smoke did not run. This is a verification
  limit, not source RED or proof that EOVERRIDE is resolved. No active jobs.
  Main must independently review candidate before a normal new commit/push,
  then require both architecture checks on the actual new PR head. No bypass,
  workflow rerun, publication or additional unbounded build was performed here.

## Checkout and changes

Task checkout: `hermes-flake/worktrees/hermes-release-update`, branch
`fix/hermes-release-update`, base `358160c02bc8c642b7aea711aa619b1884d9991f`.
Remote-main base: `b669a68cddd553edcaf5763cf4dc01af6a84b96d`.
Canonical remains on `chore/hermes-worktree-policy`; original local `main`
`e0ef43a25aed76996034c9ca7ccec88339e22581` is preserved.
Bootstrap commits only `/worktrees/` in both source ignore files.

Changes: aligned release validators, upstream-only pin, Python 3.14, common package
provenance and stronger smoke. Fresh updater fixtures cover stable/calendar
tags, malformed rejection, nonmutation and partial-lock rollback. Native tests
reject missing/wrong identity and exercise installed resolver, compatibility
import, CLI and `anthropic` extras with isolated homes. Acceptance unchanged.

## Root cause and supported adaptation

Upstream `71d34bad1045610252eda02ee79549436896e784` intentionally sets project
metadata to `0.0.0`. `hermes_cli/version_info.py:277` resolves install stamp,
then source Git, then unknown; our immutable wheel lacked both provenance and
Git. Upstream `nix/hermes-agent.nix:50-78` emits deterministic schema-2 provenance;
`pm/paths.py:21-34` supports installed code-relative stamps. Our packager copies
that schema into the shared package before variant assembly, deriving version,
commit and date from the lock and checking input revision matches. Nix/external
ownership is honest; branch/build time null, distance zero. Generated here using
upstream's mechanism, not claimed as upstream-generated.

CLI/banner, gateway status/API, ACP, desktop metrics and provider helpers share
this resolver; `__version__` reads the same stamp. Legacy `build_info` is an
intentional inert upgrade shim returning unknown, and remains untouched.
No resolver patch, fake version wrapper, Git/network lookup, package
metadata rewrite or dependency weakening. Smoke now asserts locked release and
commit instead of upstream's placeholder; binary existence checks remain.

## Evidence and limits

Private, value-free receipts are under
`/home/erik/.local/share/opencode-v2/tmp/opencode/agent-validation-20261014/`:

- `leaf-red-updater-rnpjg8a6.log`: distinct semver updater/workflow assertion failures;
  four-component calendar workflow also fails, exit 1.
- `leaf-red-pin-jh57rbat.log`: requested lock-ref assertion false, exit 1.
- `leaf-package-pipeline-1L6ChI.log`: pin succeeds, upstream-only lock diff;
  build fails Python environment assertion. Source requires ≥3.14, owner used 3.13.
- `leaf-package-repair1-m8iGnb.log`: interpreter repair builds; CLI still unknown.
- `leaf-native-smoke-clean-p2NsA6.log`: metadata-smoke fails: expected `0.0.0`,
  observed unknown. Exact release acceptance preserved throughout.
- `leaf-red-identity-controls-B5wFY7.log`: new negative controls pass, then actual
  installed identity assertion fails with unknown version and missing commit.
- `leaf-native-identity-repair1-PZm8hL.log`: first native-identity repair passes
  `just build`, isolated `just version`, base/extras identity smoke, updater,
  OCI, role-OCI, lint, schema and override. Success marker:
  `PASS hermes-release-package-modules`. Literal native proof:
  `Hermes Agent v0.21.7 (2026.9.24) · upstream 71d34bad`.
  Installed code: `/nix/store/dm8hqbfrzxffiydbgd65lykdpaaxv4rg-hermes-agent-0.0.0/lib/python3.14/site-packages`.
- `leaf-native-final-validation-rG1ClD.log`: repeat final code checks plus Bash
  syntax, notification contract and whitespace, all successful. Immutable base
  and extras smoke outputs both contain `PASS immutable-native-identity 0.21.7
  71d34bad1045610252eda02ee79549436896e784` and the same installed code path.
- RV `ses_ec7583fb0ffezEcYJ5k0fypMHJ` found package validation rejected accepted
  four-component tags. `leaf-red-provenance-compat-edESWi.log` evaluates the
  actual, exactly-once extracted package predicate in Nix: rejects
  `v2099.1.1.2, v0.21.7.1`, exit 1. One-line optional-fourth-component repair.
  Shared fixtures grade Nix package, Bash updater and workflow predicates.
  `leaf-green-provenance-compat-9BX1Af.log`: all relevant checks pass, exact
  native `0.21.7` and revision unchanged; `KEEP compatibility repair 1; EXIT 0`.
- Lint enforces formatting but masks missing `.statix.toml` and existing deadnix
  warnings; this is not strict statix/deadnix success. No unrelated cleanup.
- `leaf-upstream-zzlzbw_n/`: immutable old/new public manifests, CLI source,
  summary and actual lock-package delta. Metadata changes `0.21.5` to `0.0.0`;
  Python range extends through 3.14. Unique lock packages: 257 to 327;
  85 added, 15 removed, 79 version changes. CLI now derives version identity;
   Metadata remains untouched; no package override added speculatively.

## Continuing work and recovery

Nix exposed fixture `cmp` command-substitution behavior; explicit conditional
fixed it (`leaf-build-pipeline-dRc6n6.log`, `leaf-green-local-nix-updater-kzHLJT.log`).
Interpreter and identity repairs each passed first candidate, distinct failures.
No active jobs. Main RV and actual PR-head required CI remain: desktop, closure,
selected extras and architecture matrix. No remote owner recipe was invented.

Cache/HTTP-429 timeouts were not RED; interrupted update's own URL edit was
restored. Bootstrap identity failure created empty worktree prematurely;
approved identity then allowed commit/fast-forward before edits
(`leaf-bootstrap-thuOaN.log`). Smoke exit recorder's reserved zsh variable was
repaired in a new receipt. No discarded user work or global identity changes.

Main-session RV and real green required checks remain gates. Preserve old pins;
stop on incompatible native version or observed package failure rather than
silently changing acceptance. Main's first implementation is committed/published;
this CI repair remains an uncommitted candidate against that preserved draft.
