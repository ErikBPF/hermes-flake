# Hermes release updater and package — leaf delivery checkpoint

**Stage / revision:** final RV clear and Orion GREEN; publication candidate / 14
**Outcome:** full desktop build, mandatory desktop smoke, actual production-copy
layout fixture, stamp/native/extras identity and updater complete on Orion,
exit 0. npm security target reused cache. Code hashes unchanged; published-head
architecture CI still fails. Fresh independent RV cleared the unchanged code;
main verified staged scope, base, clean whitespace and completion evidence.
New-head protected CI remains the merge gate.
**Human seed:** `lets do both. Also check our litellm health`
**Accepted scope:** stable release handling and upstream `v0.21.7`, from homelab
`docs/plans/2026-10-14-hermes-agent-delivery.md` and its linked delivery one-pager.
Main published [PR #59](https://github.com/ErikBPF/hermes-flake/pull/59).
Four owned candidate files remain staged, uncommitted/unpublished; no merge,
deployment, workflow rerun or inference here.

## Orion transport continuation — completed

Parent authorized one additional 1200-second transport attempt on the same
candidate 4, not another repair. Same seven unique targets and Orion-only
`NIX_CONFIG` below; local `max-jobs = 0`, no fallback or host/config/credential
changes. Code stayed frozen at published base
`48b373576554207414cd00dca652eef31878a075` plus the three previously recorded
code-file hashes. This report changed only after completion.

Mode-0600 receipt:
`leaf-pr59-ci2-oqlJMv/orion-candidate4-transport-continuation-05gikm.log`.
UTC `2026-10-14T17:56:36+00:00` to `18:00:01+00:00` (205 seconds), exit 0.
Actual invocation accidentally repeated the base-smoke argument; Nix emitted
repeated smoke output paths. Seven unique outputs were verified; no extra unique
target or additional invocation. The receipt explicitly corrects its intended
command display rather than silently rewriting execution history.

Remote renderer build marker:
`building '/nix/store/ggvhgjzfbllpavx3kv3f84rrcrnagk22-hermes-desktop-renderer-0.0.0.drv' on 'ssh-ng://erik@100.72.85.73:2222'...`.
Unlike the first deadline, this receipt observes renderer check/install phases,
wrapper install, mandatory smoke build and all returned outputs. Six selected
targets have fresh Orion build/completion evidence; npm override reused cache:

| Target | Returned output basename | Evidence |
| --- | --- | --- |
| desktop | `5pvahnc2kr0v22m1jqfd9rscakfxzjjy-hermes-desktop-0.0.0` | Orion build/install/return |
| desktop-build-stamp | `4hbvcig0nak7z5g1bp8582bg2cnfgbgb-hermes-desktop-build-stamp` | Orion build/return; layout and stamp PASS |
| smoke-desktop | `8g8zhk9dlm5dndfayc2a4j9f5hqgyxzx-hermes-smoke-desktop` | Orion build/return; `ok` |
| smoke | `hf7z8ki7lb9dy9qq5w3d12f77r5iszsc-hermes-smoke` | Orion build/return; immutable identity PASS |
| release-identity-extras | `id360rabqnlqb12dklxfsmv9168fvw7g-hermes-release-identity-extras` | Orion build/return; immutable identity PASS |
| npm-workspace-overrides | `416hs2zyg5iqgsaz5bs7mvn1kzvhiaay-hermes-npm-workspace-overrides` | cached; not fresh remote execution |
| updater-mutation-only | `1dnn341qzn9bcc3qkrhw8c6lrb0avnmh-hermes-updater-mutation-only` | Orion build/return |

All output paths are under `/nix/store/`. Literal receipt/output proof:
`PASS actual-production-native-copy synthetic modules/helper layout`,
`PASS actual-electron-stamp 0.21.7 71d34bad1045610252eda02ee79549436896e784`,
and `PASS Orion-candidate4-desktop-mandatory-smoke-and-layout; EXIT 0`.
Native and extras outputs both report
`Hermes Agent v0.21.7 (2026.9.24) · upstream 71d34bad` and exact immutable revision.

Read-only artifact verification confirms nonempty renderer/main/preload/preview
files, installed PTY x86-64 ELF, no `dist/node_modules/native`, and desktop schema-2
stamp identical to installed backend stamp. Synthetic helper inputs prove layout,
not helper compilation. No GUI, native-terminal session, private profile, provider,
model-generation or ARM execution claim. Prior timeout remains infrastructure
history, not RED. Independent reviewer `ses_ec47186cdffePTgklDuSFPEr2V` cleared
normal publication conditional on completed Orion validation, now satisfied.
No active agent jobs or further retries; both protected architecture checks must
pass on the new PR head before merge.

## Bounded review blocker and resolved input

Independent reviewer `ses_ec4cdd7faffex2jZhZFZd45cXs` verified
`desktop.nix:68–69` copies prepared `native/*` to `dist/node_modules/native/*`,
but upstream helper consumers require `dist/native/*`. Existing upstream
`copyNativeTree` implements the module/helper split; retaining the generic copy
would deliver incomplete native helper paths when those helpers are compiled.
Original PTY assertion and local smoke do not cover this layout defect.

Question **Q-DESKTOP-4**, this checkout, revision 11, published base `48b3735`,
resolved APPROVED. User correction preserved verbatim:
`lets continue with repairs. Lets focus validation on orion`.
Authorization extends the cap by exactly one helper-layout candidate. No further
same-family repair is authorized; stop/report any new defect. Orion is validation
only, not the deployment target. Publication/merge/pinning/deployment still wait
for main's fresh RV and required CI. Prior drafts and RED/GREEN receipts remain.

## Candidate 4: correct helper namespace — revision-12 evidence

Current upstream `copyNativeTree` in `apps/desktop/scripts/prepared-native-deps.mjs`
puts modules under its `out` and prepared `native/*` under sibling `native/*`.
Both upstream desktop compiler and before-pack path reuse this utility. Actual
command-screenshot consumer resolves `dist/native/command-screenshot-monitor`;
HUD consumer resolves `dist/native/<platform>-<arch>/hud-modifier-monitor` (Darwin
uses `universal`). Candidate replaces generic tree copy with the same utility;
no custom platform rules, recursive copier, compiler rerun or helper fabrication.

New fixture executes the actual production native-copy phase extracted exactly
once after staging and before `popd`. Synthetic PTY/helper input bytes test module
and helper namespaces, preserved bytes and absence of `dist/node_modules/native`.
They are not compiled binaries and do not prove native execution. Real stamp
consumer/negative controls and original PTY assertion remain unchanged.

Mode-0600 receipt `leaf-pr59-ci2-oqlJMv/native-helper-layout-red-LsUCfm.log`:
local cheap fixture assertion fails before production fix,
`prepared native helper must be copied into dist/native`, exit 1. This is genuine
assertion RED, not transport/cache failure. No heavy local build for candidate 4.

Main supplied source-grounded Orion-only builder settings (desktop Justfile and
native NIX_CONFIG recipes). Invoke existing Nix package/check targets with:

```text
builders = ssh-ng://erik@100.72.85.73:2222 i686-linux,x86_64-linux,aarch64-linux /home/erik/.ssh/id_ed25519 16 2 big-parallel,benchmark,kvm,nixos-test
max-jobs = 0
builders-use-substitutes = true
```

These are per-command `NIX_CONFIG` overrides, not source/global/host changes.
Use `timeout 600 nix build .#desktop .#checks.x86_64-linux.desktop-build-stamp
.#checks.x86_64-linux.smoke-desktop .#checks.x86_64-linux.smoke
.#checks.x86_64-linux.release-identity-extras
.#checks.x86_64-linux.npm-workspace-overrides
.#checks.x86_64-linux.updater-mutation-only --print-build-logs --no-link
--print-out-paths`. Names verified in current owning source. No SSH trust/key
changes, live providers, mutable user homes, services, system switch, LAN/other
builder fallback or local heavy fallback. Remote builder log lines must prove
actual Orion sandbox execution; cached/substituted dependencies are not remote
execution proof. ARM and GUI/native-terminal runtime remain unproved.

Orion receipt `leaf-pr59-ci2-oqlJMv/orion-helper-layout-candidate4-3oomsi.log`
records UTC `2026-10-14T17:39:00+00:00` to `17:49:00+00:00`, exit 124. Exact
remote marker:
`building '/nix/store/ggvhgjzfbllpavx3kv3f84rrcrnagk22-hermes-desktop-renderer-0.0.0.drv' on 'ssh-ng://erik@100.72.85.73:2222'...`.
This establishes selected remote builder, not completed renderer compilation;
no renderer phase or desktop smoke completion was observed before timeout.
Archive copying was still in progress; `error: interrupted by the user` is the
deadline termination, not an assertion failure. No retry or fallback was run.

Observed completed remote outputs (each has matching Orion build and returned
store-path lines, not merely cache substitution):

- Native identity: `/nix/store/msl1yvdsnd904zdzmycq8hdw0yrwmyc1-hermes-smoke`.
- Anthropic extras identity:
  `/nix/store/rgv9z0803wfq33vbli315q1j23x84ckl-hermes-release-identity-extras`.
  Both contain `PASS immutable-native-identity 0.21.7 71d34bad1045610252eda02ee79549436896e784`
  and real `Hermes Agent v0.21.7 (2026.9.24) · upstream 71d34bad` output.
- Updater: `/nix/store/r2k6fxf48v4aj6rnz2iwj2vi1zyqmrhc-hermes-updater-mutation-only`.
- Production copy-phase text: `/nix/store/8d4lbh3gljhzfb64yp04jb1p4wwjfsp1-desktop-native-copy-phase.sh`.
  This text derivation completed; it does not prove the layout fixture ran remotely.

Layout check `/nix/store/636qpf9nxsk508cvb5hvlrk2wp9hkdnk-hermes-desktop-build-stamp.drv`
has an Orion build marker but no observed returned result. Desktop wrapper and
mandatory smoke completion remain unobserved. npm override check was cached/evaluated,
not fresh Orion runtime proof. No active agent jobs; remote daemon completion
after deadline was not inspected.

Cheap direct source diagnosis after timeout, without any further Nix build:
`leaf-pr59-ci2-oqlJMv/native-helper-layout-source-green-DvQm9v.log`, exit 0.
Existing Node test executes the actual copy-phase file returned by Orion against
synthetic prepared input, checks correct paths and wrong-namespace absence, then
passes real stamp consumer controls. Literal marker:
`PASS actual-production-native-copy synthetic modules/helper layout`.
Fresh npm derivation evaluation also passes exact security assertions. These two
cheap checks are source GREEN only, not full Orion validation or native execution.
At revision 12, further bounded Orion validation and main RV remained waiting
work. The single authorized transport continuation above resolves validation;
main fresh RV and publication/CI gates remain.
Final source receipt `leaf-pr59-ci2-oqlJMv/helper-layout-final-source-WN3JtO.log`
records the three code-file SHA-256 hashes, formatting/whitespace success,
byte-identical original PTY assertion and unchanged lock/provenance/npm security/
updater/workflows. All receipts remain `0600`; exactly four owned files staged.

## Current desktop stamp candidate

Verified checkout, PR and run head:
`48b373576554207414cd00dca652eef31878a075`. Run `38587735702` failed
`build Hermes Desktop` on both
[x86](https://github.com/ErikBPF/hermes-flake/actions/runs/38587735702/job/115934132194)
and [ARM](https://github.com/ErikBPF/hermes-flake/actions/runs/38587735702/job/115934132327):
`Error: Invalid desktop stamp payload: undefined` from actual upstream
`bundle-electron-main.mjs:18`. Both logs first show completed Vite compilation;
the previous npm error is resolved, not merely hidden.

Root cause: owner `desktop.nix` still emitted a schema-1 placeholder with fake
`commit: "nix"` and no payload. Candidate 1 copies the installed backend's real
schema-2 Nix provenance into desktop preparation instead. Same immutable release,
revision and external update ownership; no fabricated fields, oracle weakening
or project metadata rewrite. A renderer passthru exposes the actual stamp-writing
build-phase prefix for a narrow test seam, without running a substitute compiler.

Receipts are under `leaf-pr59-ci2-oqlJMv/`, all mode `0600`:

- `run.json`, `x86-failed.log`, `arm-failed.log`: actual current-head failures.
- `local-stamp-red-59oRii.log`: real stamp-writing prefix plus exactly-once
  extracted upstream `productIdentity` function reproduces identical error, exit 1.
- `local-stamp-green-Fv4I88.log`: same consumer passes, rejecting missing/invalid
  payload controls and validating true version/revision/schema/ownership. Literal
  proof: `PASS actual-electron-stamp 0.21.7 71d34bad1045610252eda02ee79549436896e784`.
  Native/extras, npm, updater, OCI/config and existing lint regressions pass;
  ARM stamp-check evaluation succeeds, not ARM runtime validation.
- `desktop-stamp-candidate1-ol6Qnb.log`: job `sh_13b095947001tfOC2iAJryyVyt`
  completed exit 1, not timeout. Real main/preload/preview bundling and native
  staging succeed; checkPhase then fails `npm error Missing script: "postbuild"`.
  Current upstream desktop manifest has no such script. Existing owner buildPhase
  already invokes bundling/staging directly. Native-PTY presence check remains
  untouched and was not reached; desktop smoke did not run. Optional X11 HUD
  compiler warning explicitly says packaging continues, so it is not this blocker.
  This attempt's blocker is resolved below; retain the genuine failed receipt.

## Obsolete hook and native-tree delivery

Main reported independent source RV of revision-9 stamp candidate READY
(`ses_ec4f04cdfffe5BEbFbK8xV4W5B`). Additional hook/tree edits still need main RV.
Grounded upstream manifest: no `postbuild` script; `build` invokes
`scripts/build.mjs`, which prepares native inputs and calls the desktop compiler.
Owner buildPhase already invokes actual main/preload/preview bundling and native
staging directly. Candidate 2 removes only the obsolete script call, checking
nonempty renderer/main/preload/preview outputs instead. Original staged PTY
assertion, native compiler/stager and mandatory smoke remain intact.

Candidate 2's full build then exposes a real namespace mismatch: upstream CLI
now stages into `apps/desktop/build/native-deps`, while runtime module resolution,
installation and unchanged PTY check require `dist/node_modules`. Candidate 3
copies that prepared native tree into the runtime namespace; no recompilation,
source patch, fake binary or relaxed assertion. A direct `--out dist/node_modules`
would violate upstream's supported generated-destination policy; keep preparation
in its supported home, then install its result. At revision 10 this was the
third/final allowed desktop-family repair; Q-DESKTOP-4 above explicitly extends
authorization by one helper-layout candidate, not an unbounded repair loop.

Additional mode-0600 receipts in `leaf-pr59-ci2-oqlJMv/`:

- `local-postbuild-red-f954aG.log`: actual checkPhase script names checked against
  locked manifest; assertion fails `desktop checkPhase references absent script:
  postbuild`, exit 1. Prior full-build missing-script error is also genuine RED.
- `local-postbuild-green-xgAHB1.log`: manifest regression and real upstream stamp
  consumer pass; ARM evaluation only.
- `desktop-postbuild-candidate2-naq47J.log`: actual full build passes new output
  checks, then unchanged PTY guard fails: `FATAL: Missing staged node-pty native
  binary at ./dist/node_modules/node-pty/build/Release/pty.node`, exit 1. Real RED
  for candidate 3, not infrastructure failure.
- `desktop-native-tree-candidate3-V3l5ce.log`: actual full desktop build and
  mandatory smoke pass within a 600-second campaign deadline, exit 0. Literal
  markers: `PASS local-x86-hermes-desktop-native-tree-candidate3` and
  `PASS local-x86-desktop-smoke-native-identity-and-stamp`. Native CLI reports
  `Hermes Agent v0.21.7 (2026.9.24) · upstream 71d34bad`. Built wrapper:
  `/nix/store/jf8if4ixb50qks9gzhrb01lr57p0b43r-hermes-desktop-0.0.0`; native PTY
  is installed under its `share/hermes-desktop/dist/node_modules/node-pty/build/Release/`.
  Desktop smoke checks executable/artifacts and real backend-wrapper binding;
  it is not a GUI launch or native-terminal execution test.
- `desktop-final-regression-09qzw4.log`: final cached desktop/stamp/native/extras,
  npm, updater, OCI/config and existing lint checks pass, exit 0; ARM desktop and
  smoke derivations evaluate only. Installed artifacts are nonempty, PTY has an
  x86-64 ELF header, and installed desktop stamp equals installed backend stamp.
  Original PTY assertion is byte-identical to HEAD; lock/package/npm/updater and
  workflow files are unchanged. Existing masked statix/deadnix limits still apply.

No active jobs. No lock, Python, native identity resolver/generator, npm security
override or updater changes. Main RV precedes normal commit/push; require both
protected architecture checks on the next actual PR head before merge/deployment.

## Previous npm CI repair (published)

Verified checkout, PR and run head:
`2195d6af6e3b2df069c8bec838c6dbd2da060fe7`. Run `38583250103` failed
`build Hermes Desktop` on both
[x86](https://github.com/ErikBPF/hermes-flake/actions/runs/38583250103/job/115918386882)
and [ARM](https://github.com/ErikBPF/hermes-flake/actions/runs/38583250103/job/115918387470):
`npm error code EOVERRIDE`, direct `js-yaml` file URL conflicts with override.
These are observed source/build failures, not download infrastructure failures.

Root cause: `importNpmLock` rewrites direct dependencies to locked file URLs but
leaves override literal `4.3.1`. Published candidate 1 changes only shared `lib.nix` adapter
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
  Main independently reviewed and published normal repair commit `48b3735`;
  subsequent protected CI confirms npm configuration and renderer compilation
  now pass. No bypass or additional unbounded build was performed here.

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
these desktop repairs remain uncommitted candidates against that preserved draft.
