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
      after = ["hermes-agent.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = let
          # Use loopback when the service is bound everywhere (0.0.0.0 / ::);
          # otherwise probe whatever address it's actually listening on.
          probeHost =
            if cfg.openBindAddress == "0.0.0.0"
            then "127.0.0.1"
            else if cfg.openBindAddress == "::"
            then "::1"
            else cfg.openBindAddress;
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
