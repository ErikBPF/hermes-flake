# Isolation Options

Trade-off matrix for the host where hermes-agent runs 24/7.

| Approach | Module exposed | Isolation level | Overhead | Declarative | Snapshot-friendly |
|---|---|---|---|---|---|
| **Bare-metal NixOS** | `nixosModules.default` | systemd hardening only | 0 | ✅ | btrfs subvolume |
| **nixos-container** (this flake) | `nixosModules.hermes-agent-container` | namespace isolation (mnt, pid, uts, ipc) | ~10 MB extra RAM | ✅ | container fs = subvolume |
| **microvm.nix** | — (DIY) | full VM (kernel-level) | 50-150 MB RAM, kvm | ✅ | image-level snapshots |
| **podman quadlet** | — (DIY) | cgroups + namespaces | ~5 MB | partial (quadlet YAML) | volume bind |
| **Docker compose** | — (current) | cgroups + namespaces | ~5 MB | imperative YAML | volume bind |

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

## microvm.nix (if you want VM-grade)

Out of scope for this flake (the `microvm.nixosModules.microvm` wraps any NixOS config, not specific to hermes). Sketch:

```nix
{
  imports = [ microvm.nixosModules.microvm ];
  microvm = {
    hypervisor = "qemu";
    mem = 1024;
    vcpu = 2;
    shares = [{
      tag = "hermes-data";
      source = "/var/lib/hermes-agent";
      mountPoint = "/var/lib/hermes-agent";
    }];
  };
  imports = [ hermes-flake.nixosModules.default ];
  services.hermes-agent.enable = true;
}
```

Doable but adds ~100 MB RAM idle. Worth it only if you don't trust the host kernel boundary.

## podman (alternative without leaving this flake's ecosystem)

If you want podman-style without NixOS containers, build a docker image with the package and run via `virtualisation.oci-containers`:

```nix
virtualisation.oci-containers.containers.hermes-agent = {
  image = "localhost/hermes-agent:nix";
  imageFile = pkgs.dockerTools.buildImage {
    name = "hermes-agent";
    tag = "nix";
    contents = [ inputs.hermes-flake.packages.${pkgs.system}.hermes-agent ];
    config.Cmd = [ "/bin/hermes" "gateway" "run" ];
  };
  environment = { /* same as services.hermes-agent.environment */ };
  environmentFiles = [ config.sops.secrets."hermes-agent/env".path ];
  ports = [ "8642:8642" "8644:8644" ];
  volumes = [ "/var/lib/hermes-agent:/var/lib/hermes-agent" ];
};
```

Out of scope to ship this — easy to derive if needed.
