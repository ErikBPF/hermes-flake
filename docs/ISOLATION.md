# Isolation Options

Trade-off matrix for the host where hermes-agent runs 24/7.

| Approach | Module exposed | Isolation level | Overhead | Declarative | Snapshot-friendly |
|---|---|---|---|---|---|
| **Bare-metal NixOS** | `nixosModules.default` | systemd hardening only | 0 | ✅ | btrfs subvolume |
| **nixos-container** (this flake) | `nixosModules.hermes-agent-container` | namespace isolation (mnt, pid, uts, ipc) | ~10 MB extra RAM | ✅ | container fs = subvolume |
| **microvm.nix** (this flake) | `nixosModules.hermes-agent-microvm` | full VM (kernel-level) | ~100 MB RAM, kvm | ✅ | image-level snapshots |
| **podman/docker** (this flake) | `nixosModules.hermes-agent-podman` | cgroups + namespaces | ~5 MB | ✅ (declarative OCI image via dockerTools) | volume bind |

## Recommendation by need

- **"Just works, declaratively"** → Bare-metal NixOS module. Hardening directives already block most attack surface. Easier to debug, no double-NixOS dance.
- **"Docker-like isolation without Docker"** → nixos-container. Same containers.* declarative model as Docker, but native NixOS, snapshot-friendly, no daemon.
- **"Strongest isolation, willing to pay overhead"** → microvm.nix. Hermes runs in a real KVM VM with its own kernel. Hardest to escape from.
- **"Keep current podman/Docker workflow"** → don't use this flake's modules. Run as container with `docker run ghcr.io/nousresearch/hermes-agent` (upstream image).

## nixos-container quick reference

The `hermes-agent-container` module spins a systemd-nspawn container:

```nix
services.hermes-agent-container = {
  enable = true;
  containerName = "hermes";
  privateNetwork = false;  # share host net (simpler)
  hostDataDir = "/var/lib/hermes-agent";
  hostSecretsPath = config.sops.secrets."hermes-agent/env".path;
  telegramAllowedUsers = [ 123456789 ];
};
```

### Operating it

```fish
# Status
sudo machinectl list
sudo machinectl status hermes
sudo systemctl status container@hermes

# Logs
sudo journalctl -M hermes -u hermes-agent -f

# Shell inside
sudo machinectl shell hermes
# from inside: systemctl status hermes-agent

# Restart
sudo systemctl restart container@hermes

# Stop / start
sudo machinectl stop hermes
sudo machinectl start hermes
```

### Network modes

**`privateNetwork = false`** (default)
- Container shares host network namespace.
- `services.hermes-agent.openBindAddress = "0.0.0.0"` binds host's 8642/8644 directly.
- SWAG `set $upstream_app 127.0.0.1;` works unchanged.
- Pro: zero networking complexity.
- Con: container can see all host sockets; less isolation.

**`privateNetwork = true`**
- Container gets its own veth + bridge.
- Use `forwardPorts` to expose host:8642 → container:8642.
- SWAG still uses `127.0.0.1:8642`.
- Pro: container can't see other host services on `localhost`.
- Con: outbound NAT — needs host iptables/nftables rule for the container subnet to reach the internet (NixOS does this automatically via `networking.nat.enable`).

### Snapshots (btrfs)

The hostDataDir is a btrfs subvolume (bootstrap inside the inner `services.hermes-agent` creates it). Snapshot from host:

```fish
sudo btrfs subvolume snapshot -r /var/lib/hermes-agent /var/lib/snapshots/hermes-$(date +%Y%m%d-%H%M)
```

Send/receive to an offsite host (e.g. over Tailscale):

```fish
sudo btrfs send /var/lib/snapshots/hermes-... | ssh voyager 'sudo btrfs receive /backup/hermes/'
```

## microvm.nix (VM-grade isolation)

First-class module: `nixosModules.hermes-agent-microvm`. Wraps the base service inside a microvm with its own kernel, virtio-9p shares for `dataDir` + secrets, and qemu user-net port forwards by default.

Host requirements:

```nix
# host configuration.nix
imports = [
  inputs.microvm.nixosModules.host
  inputs.hermes-flake.nixosModules.hermes-agent-microvm
];

services.hermes-agent-microvm = {
  enable = true;
  memMB = 2048;
  vcpu = 2;
  hypervisor = "qemu";   # or "cloud-hypervisor" / "firecracker" / "crosvm"
  hostDataDir = "/var/lib/hermes-agent";
  hostSecretsPath = config.sops.secrets."hermes-agent/env".path;
  extras = [ "voice" "anthropic" ];
  telegramAllowedUsers = [ 123456789 ];
};
```

`microvm` is shipped as an optional flake input — pulling the host module via `inputs.microvm.nixosModules.host` is required on the host before the wrapper module evaluates (a clear assertion fires if missing).

Trade-offs vs `nixos-container`:

| Axis | container (nspawn) | microvm |
|---|---|---|
| Kernel | host's | dedicated guest kernel |
| RAM overhead | ~10 MB | ~100 MB idle |
| Boot time | ms | ~2-5 s |
| Network isolation | shared netns or veth | full isolation (TAP/user-net) |
| Escape surface | container syscalls | hypervisor + virtio |
| Use this when | trust host, want declarative isolation | strong adversarial threat model, don't trust host kernel |

## podman / docker

First-class module: `nixosModules.hermes-agent-podman`. Builds an OCI image via `dockerTools.buildLayeredImage` containing the hermes-agent venv, runs via `virtualisation.oci-containers` against your chosen backend (podman or docker).

```nix
imports = [ inputs.hermes-flake.nixosModules.hermes-agent-podman ];

services.hermes-agent-podman = {
  enable = true;
  backend = "podman";   # or "docker"
  extras = [ "voice" "anthropic" "mcp" ];
  environmentFile = config.sops.secrets."hermes-agent/env".path;
  hostDataDir = "/var/lib/hermes-agent";
  apiPort = 8642;
  webhookPort = 8644;
};
```

Defaults to `--read-only`, `--cap-drop=ALL`, `--cap-add=NET_BIND_SERVICE`, `--security-opt=no-new-privileges`, `--tmpfs=/tmp`. State persists via the `hostDataDir` bind mount.

UID inside the container = 10000 (matches the bare-metal and container variants for migration compatibility).
