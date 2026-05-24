# Shared option definitions + forwarding helper for the wrapper modules
# (container, microvm, podman). Keeps the wrapper APIs in sync with the
# base `services.hermes-agent` module so every consumer-facing knob is
# settable at the wrapper level, not via the untyped escape hatch.
{
  lib,
  pkgs,
}:
with lib; rec {
  # Option set to splat into every wrapper's `options.<service>` attrset.
  # Wrappers add their isolation-specific options on top (containerName,
  # hypervisor, backend, etc.).
  options = {
    extras = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Upstream hermes-agent extras to include.";
      example = ["voice" "anthropic" "mcp"];
    };

    apiPort = mkOption {
      type = types.port;
      default = 8642;
    };

    webhookPort = mkOption {
      type = types.port;
      default = 8644;
    };

    openBindAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      example = "0.0.0.0";
    };

    openaiBaseUrl = mkOption {
      type = types.str;
      default = "https://api.openai.com/v1";
    };

    telegramAllowedUsers = mkOption {
      type = types.listOf types.int;
      default = [];
    };

    telegramAllowedChats = mkOption {
      type = types.listOf types.str;
      default = [];
    };

    telegramAllowedTopics = mkOption {
      type = types.listOf types.str;
      default = [];
    };

    apiServerCorsOrigins = mkOption {
      type = types.listOf types.str;
      default = [];
    };

    apiServerModelName = mkOption {
      type = types.str;
      default = "";
    };

    maxIterations = mkOption {
      type = types.int;
      default = 90;
    };

    profile = mkOption {
      type = types.nullOr types.str;
      default = null;
    };

    enableDashboard = mkOption {
      type = types.bool;
      default = false;
    };

    dashboardHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
    };

    dashboardPort = mkOption {
      type = types.port;
      default = 9119;
    };

    settings = mkOption {
      type = (pkgs.formats.yaml {}).type;
      default = {};
      description = "Forwarded to inner services.hermes-agent.settings.";
    };

    soulFile = mkOption {
      type = types.nullOr types.path;
      default = null;
    };

    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
    };

    memoryMax = mkOption {
      type = types.nullOr types.str;
      default = null;
    };

    cpuQuota = mkOption {
      type = types.nullOr types.str;
      default = null;
    };

    enableHealthcheck = mkOption {
      type = types.bool;
      default = true;
    };

    healthcheckInterval = mkOption {
      type = types.str;
      default = "60s";
    };

    extraServiceDeps = mkOption {
      type = types.listOf types.str;
      default = [];
    };
  };

  # Build the `services.hermes-agent = {...}` attrset to set inside the
  # inner NixOS config (container guest, microvm guest, etc.) from the
  # wrapper's own cfg. Nullable options use lib.optionalAttrs so they only
  # appear when actually set — matches inner module's semantics.
  toInner = cfg:
    {
      enable = true;
      inherit
        (cfg)
        extras
        apiPort
        webhookPort
        openBindAddress
        openaiBaseUrl
        telegramAllowedUsers
        telegramAllowedChats
        telegramAllowedTopics
        apiServerCorsOrigins
        apiServerModelName
        maxIterations
        enableDashboard
        dashboardHost
        dashboardPort
        settings
        enableHealthcheck
        healthcheckInterval
        extraServiceDeps
        ;
    }
    // (lib.optionalAttrs (cfg.profile != null) {inherit (cfg) profile;})
    // (lib.optionalAttrs (cfg.soulFile != null) {inherit (cfg) soulFile;})
    // (lib.optionalAttrs (cfg.configFile != null) {inherit (cfg) configFile;})
    // (lib.optionalAttrs (cfg.memoryMax != null) {inherit (cfg) memoryMax;})
    // (lib.optionalAttrs (cfg.cpuQuota != null) {inherit (cfg) cpuQuota;});
}
