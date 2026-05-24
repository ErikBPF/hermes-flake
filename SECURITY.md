# Security Policy

## Reporting a vulnerability

Report security issues by opening a [GitHub Security Advisory](https://github.com/ErikBPF/hermes-flake/security/advisories/new). Do not file a public issue for unpatched vulnerabilities.

Expect an acknowledgement within 5 business days.

## Scope

In scope:

- Defects in the flake itself: nix derivation, NixOS module, container/microvm/podman wrappers, build scripts.
- Default values that lead to insecure deployments.
- Documentation that misleads consumers into insecure configurations.

Out of scope (report to NousResearch directly):

- Defects in `hermes-agent` itself — the upstream Python codebase.
- Vulnerabilities in upstream Python dependencies (uv.lock pins).
- LLM provider account compromise.

## Threat model

The flake assumes:

- Hosts running the bare-metal NixOS module trust their own kernel.
- The `dataDir` filesystem is on a trusted disk.
- `environmentFile` (sops-rendered dotenv) is readable only by the `hermes` user (mode `0400` or `0440` + group membership).
- LLM API endpoints (`openaiBaseUrl`) are reached over HTTPS with valid certificates.
- Telegram/Discord bot tokens are user-scoped and revocable.

## Hardening defaults

The flake ships baseline process safety required for the lazy-install behavior to work:

- `NoNewPrivileges=true`
- `PrivateTmp=true`
- `ProtectSystem=strict`
- `ProtectHome=read-only`
- `ReadWritePaths=[${dataDir}]`

Kernel-level hardening (`ProtectKernelTunables`, `ProtectKernelModules`, etc.) is **not** prescribed — host policy is consumer-driven. Apply via standard NixOS overrides if your threat model warrants it. See README § "systemd" for the full list of recommended additions.

## Container variants

Each isolation wrapper trades surface area for runtime cost. Choose based on your trust boundary:

| Wrapper | Use when |
|---|---|
| `nixosModules.default` (bare-metal) | trusted host; you maintain kernel + base OS |
| `hermes-agent-container` (nspawn) | want declarative isolation, namespace-only |
| `hermes-agent-podman` | want OCI tooling, daemon-managed lifecycle |
| `hermes-agent-microvm` | adversarial threat model, don't trust kernel boundary |

See [`docs/ISOLATION.md`](docs/ISOLATION.md) for the full trade-off matrix.

## Assertions enforced

- `openBindAddress != "127.0.0.1"` ⇒ `environmentFile != null` (otherwise the API server is exposed unauthenticated).
- Build-time hash verification on the upstream `hermes-agent-src` flake input (via `flake.lock`).

## Known caveats

- The systemd unit's `EnvironmentFile=` is dereferenced by systemd as root before `User=hermes` kicks in — the secret file must be readable by root and by `hermes` (typically `mode = "0440"; owner = "hermes"; group = "hermes";` via sops-nix).
- `services.hermes-agent-microvm` shares the parent directory of `hostSecretsPath` over virtiofs. Place the secret file in its own subdirectory (e.g. `/run/secrets/hermes-agent/env`) to scope the share — otherwise the guest can list other secrets in the same directory.
- `services.hermes-agent-podman` reads `environmentFile` via `podman --env-file`. The runtime backend's view of the file is what gets injected — runtime-resolved by the container runtime, not by sops-nix.
- Lazy-installed dependencies under `${dataDir}` are not in the nix store and not subject to nix's hash verification. Treat `${dataDir}` as user-mutable state, not as a security boundary.

## Dependency provenance

- `hermes-agent-src` is pinned to a specific upstream git tag in `flake.nix`. The `flake.lock` records the source's tree hash. Hourly auto-update PRs bump the pin; each PR is gated on `nix flake check` passing before auto-merge.
- Python dependency hashes come from upstream's `uv.lock`. Pre-built wheels and sdists are fetched by `uv2nix` with content hashes; tampering invalidates the build.
- The flake does not introduce its own pre-built binaries — everything is reproducible from source via uv2nix + pyproject-nix.
