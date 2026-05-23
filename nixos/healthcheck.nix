# Optional healthcheck timer — polls /health on the API server every
# `cfg.healthcheckInterval` (default 60s) and logs failures to journal.
#
# Does NOT restart the service on failure — wire to your monitoring stack
# (Alloy/Grafana/Healthchecks/etc.) if you want pager behavior.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hermes-agent;
in {
  config = lib.mkIf (cfg.enable && cfg.enableHealthcheck) {
    systemd.services.hermes-agent-healthcheck = {
      description = "Hermes Agent healthcheck";
      # `after` orders this oneshot against the main unit's start, but
      # `requisite` is what makes it a no-op when the main service is
      # stopped/failed — without requisite the timer fires every tick
      # against a dead service, spamming the journal with false failures.
      after = ["hermes-agent.service"];
      requisite = ["hermes-agent.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = let
          inherit (import ./wrapper-options.nix {inherit lib pkgs;}) probeHostFor;
          probeHost = probeHostFor cfg.openBindAddress;
        in
          pkgs.writeShellScript "hermes-healthcheck" ''
            ${pkgs.curl}/bin/curl -fsS --max-time 5 --connect-timeout 3 \
              "http://${probeHost}:${toString cfg.apiPort}/health" > /dev/null
          '';
      };
    };

    systemd.timers.hermes-agent-healthcheck = {
      description = "Hermes Agent healthcheck timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = cfg.healthcheckInterval;
      };
    };
  };
}
