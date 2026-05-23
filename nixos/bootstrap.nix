# Bootstrap script run as `ExecStartPre=+...` (root) before the hermes
# service drops to its unprivileged user.
#
# Idempotent. Creates the dataDir (as a btrfs subvolume when possible),
# chowns it to the service user, and stages the nix-generated config.yaml
# and SOUL.md into the dataDir so the service can edit them at runtime if
# needed (hermes writes things like `auth.json` next to its config).
{
  pkgs,
  dataDir,
  user,
  group,
  configFile,
  soulFile,
}:
pkgs.writeShellScript "hermes-bootstrap" ''
  set -euo pipefail

  freshly_created=0
  if [ ! -d "${dataDir}" ]; then
    parent=$(${pkgs.coreutils}/bin/dirname "${dataDir}")
    fstype=$(${pkgs.util-linux}/bin/findmnt -no FSTYPE "$parent" 2>/dev/null || echo "")
    if [ "$fstype" = "btrfs" ]; then
      ${pkgs.btrfs-progs}/bin/btrfs subvolume create "${dataDir}"
    else
      ${pkgs.coreutils}/bin/mkdir -p "${dataDir}"
    fi
    freshly_created=1
  fi

  # On restart with an existing dataDir: chown the dir itself only. A
  # recursive chown can race with the running service's open writers
  # (lazy-installed venv, sessions/, sqlite WAL) and hermes creates new
  # files under its own UID/GID anyway.
  #
  # On first creation (or when the operator has dropped files inside as
  # root via `sudo cp`), fall back to chown -R so the service can read
  # everything. The freshly_created flag covers the first-boot case;
  # operator recovery is documented as a one-shot:
  #   sudo chown -R ${user}:${group} "${dataDir}"
  if [ "$freshly_created" = "1" ]; then
    ${pkgs.coreutils}/bin/chown -R ${user}:${group} "${dataDir}"
  else
    ${pkgs.coreutils}/bin/chown ${user}:${group} "${dataDir}"
  fi
  ${pkgs.coreutils}/bin/chmod 0750 "${dataDir}"

  # Install the nix-rendered config.yaml + SOUL.md ONLY when missing.
  # Hermes may mutate these at runtime (auth tokens, profile creation,
  # personality edits); reinstalling on every restart would destroy that
  # state. To re-seed after a config schema change in the flake, delete
  # the file manually:
  #   sudo rm ${dataDir}/config.yaml; systemctl restart hermes-agent
  [ -e "${dataDir}/config.yaml" ] || ${pkgs.coreutils}/bin/install -m 0640 \
    -o ${user} -g ${group} ${configFile} "${dataDir}/config.yaml"
  [ -e "${dataDir}/SOUL.md" ] || ${pkgs.coreutils}/bin/install -m 0640 \
    -o ${user} -g ${group} ${soulFile} "${dataDir}/SOUL.md"

  # Regardless of install path, normalize ownership + mode on the staged
  # files (in case operator hand-edited as root or permissions drifted).
  ${pkgs.coreutils}/bin/chown ${user}:${group} \
    "${dataDir}/config.yaml" "${dataDir}/SOUL.md" 2>/dev/null || true
  ${pkgs.coreutils}/bin/chmod 0640 \
    "${dataDir}/config.yaml" "${dataDir}/SOUL.md" 2>/dev/null || true
''
