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

  if [ ! -d "${dataDir}" ]; then
    parent=$(${pkgs.coreutils}/bin/dirname "${dataDir}")
    fstype=$(${pkgs.util-linux}/bin/findmnt -no FSTYPE "$parent" 2>/dev/null || echo "")
    if [ "$fstype" = "btrfs" ]; then
      ${pkgs.btrfs-progs}/bin/btrfs subvolume create "${dataDir}"
    else
      ${pkgs.coreutils}/bin/mkdir -p "${dataDir}"
    fi
  fi

  # Set ownership only on the directory itself, not -R: the running service
  # may be writing files inside (lazy-installed venv, sessions/, sqlite WAL)
  # and a recursive chown during restart can race with open writers. Hermes
  # creates new files under its own UID/GID anyway.
  ${pkgs.coreutils}/bin/chown ${user}:${group} "${dataDir}"
  ${pkgs.coreutils}/bin/chmod 0750 "${dataDir}"

  # Install the nix-rendered config.yaml + SOUL.md ONLY when they are missing
  # OR when their content differs from the nix-rendered version. Hermes may
  # mutate these at runtime (auth setup, profile creation); blind overwrite
  # on every restart would destroy that state.
  ${pkgs.coreutils}/bin/install -C -m 0640 -o ${user} -g ${group} \
    ${configFile} "${dataDir}/config.yaml"
  ${pkgs.coreutils}/bin/install -C -m 0640 -o ${user} -g ${group} \
    ${soulFile} "${dataDir}/SOUL.md"
''
