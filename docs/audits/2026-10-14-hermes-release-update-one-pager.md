# Hermes release updater and package — leaf delivery checkpoint

**Stage / revision:** L1/L2 implementation GREEN; P2 compatibility repair verified; main RV and required CI pending / 7
**Outcome:** requested upstream `v0.21.7` builds and reports native `0.21.7` with
the actual locked revision; base/extras smoke, updater, OCI and config checks pass.
**Human seed:** `lets do both. Also check our litellm health`
**Accepted scope:** stable release handling and upstream `v0.21.7`, from homelab
`docs/plans/2026-10-14-hermes-agent-delivery.md` and its linked delivery one-pager.
No publication, merge, deployment, or runtime inference performed here.

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
silently changing acceptance. Bootstrap is the only new commit so far.
