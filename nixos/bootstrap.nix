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

  ${pkgs.coreutils}/bin/chown -R ${user}:${group} "${dataDir}"
  ${pkgs.coreutils}/bin/chmod 0750 "${dataDir}"

  ${pkgs.coreutils}/bin/install -m 0640 -o ${user} -g ${group} \
    ${configFile} "${dataDir}/config.yaml"
  ${pkgs.coreutils}/bin/install -m 0640 -o ${user} -g ${group} \
    ${soulFile} "${dataDir}/SOUL.md"
''
