{
  pkgs,
  lib,
  self,
  system,
}: let
  hermes = self.packages.${system}.hermes-agent;
  hermesFull = self.packages.${system}.hermes-agent-full;
in {
  # ── Smoke — base variant ─────────────────────────────────────────────────
  smoke = pkgs.runCommand "hermes-smoke" {} ''
    version=$(${hermes}/bin/hermes --version)
    case "$version" in
      *"Hermes Agent v0.14.0"*) ;;
      *) echo "unexpected version: $version" >&2; exit 1 ;;
    esac

    # All three entrypoints exist
    test -x ${hermes}/bin/hermes
    test -x ${hermes}/bin/hermes-agent
    test -x ${hermes}/bin/hermes-acp

    echo "$version" > $out
  '';

  # ── Smoke — full variant ─────────────────────────────────────────────────
  smoke-full = pkgs.runCommand "hermes-smoke-full" {} ''
    version=$(${hermesFull}/bin/hermes --version)
    case "$version" in
      *"Hermes Agent v0.14.0"*) ;;
      *) echo "unexpected version: $version" >&2; exit 1 ;;
    esac
    echo "$version" > $out
  '';

  # ── Config renderer — discord MUST be top-level, NOT platforms.discord ───
  config-yaml-schema = let
    rendered = import ./config.yaml.nix {
      inherit pkgs lib;
      settings = {};
    };
  in
    pkgs.runCommand "hermes-config-yaml-schema" {} ''
      yaml=$(${pkgs.coreutils}/bin/cat ${rendered})
      echo "$yaml" > $out

      # discord must be top-level
      echo "$yaml" | grep -q '^discord:' || (echo "discord: not at top level" >&2; exit 1)

      # platforms section exists and registers api_server, webhook, telegram
      echo "$yaml" | grep -q '^platforms:' || (echo "platforms: section missing" >&2; exit 1)

      indented_section=$(${pkgs.gnused}/bin/sed -n '/^platforms:/,/^[a-z]/p' <<<"$yaml")
      echo "$indented_section" | grep -q '  api_server:' || (echo "platforms.api_server missing" >&2; exit 1)
      echo "$indented_section" | grep -q '  webhook:' || (echo "platforms.webhook missing" >&2; exit 1)
      echo "$indented_section" | grep -q '  telegram:' || (echo "platforms.telegram missing" >&2; exit 1)

      # discord MUST NOT appear under platforms
      if echo "$indented_section" | grep -q '  discord:'; then
        echo "discord: appears under platforms (schema bug — should be top-level)" >&2
        exit 1
      fi
    '';

  # ── Config renderer — user settings override defaults ────────────────────
  config-yaml-override = let
    rendered = import ./config.yaml.nix {
      inherit pkgs lib;
      settings = {
        agent.max_turns = 120;
        model.default = "claude-opus-4-7";
        memory.nudge_interval = 5;
      };
    };
  in
    pkgs.runCommand "hermes-config-yaml-override" {} ''
      yaml=$(${pkgs.coreutils}/bin/cat ${rendered})
      echo "$yaml" > $out

      ${pkgs.gnused}/bin/sed -n '/^agent:/,/^[a-z]/p' <<<"$yaml" | grep -q 'max_turns: 120' \
        || (echo "agent.max_turns override didn't apply" >&2; exit 1)
      ${pkgs.gnused}/bin/sed -n '/^model:/,/^[a-z]/p' <<<"$yaml" | grep -q 'default: claude-opus-4-7' \
        || (echo "model.default override didn't apply" >&2; exit 1)
      ${pkgs.gnused}/bin/sed -n '/^memory:/,/^[a-z]/p' <<<"$yaml" | grep -q 'nudge_interval: 5' \
        || (echo "memory.nudge_interval override didn't apply" >&2; exit 1)
    '';

  # ── NixOS VM test — boots a VM, asserts the module produces a valid unit ─
  # Validates: module evaluates in real NixOS context, user/group created
  # with UID/GID 10000, systemd unit present + hardened, env vars exported.
  # The agent itself is NOT started (it would try to contact LiteLLM) — we
  # just check the unit configuration is correct.
  nixos-module = pkgs.testers.runNixOSTest {
    name = "hermes-agent-module";

    nodes.machine = {
      config,
      lib,
      pkgs,
      ...
    }: {
      imports = [self.nixosModules.default];

      # Provide a fake EnvironmentFile so the unit can start (we won't start it).
      environment.etc."hermes-agent-fake-env".text = ''
        OPENAI_API_KEY=test
        LITELLM_API_KEY=test
        API_SERVER_KEY=test
        HERMES_TELEGRAM_BOT_TOKEN=test
      '';

      services.hermes-agent = {
        enable = true;
        environmentFile = "/etc/hermes-agent-fake-env";
        telegramAllowedUsers = [42 7729797827];
        telegramAllowedChats = ["-1001234567890"];
        apiServerCorsOrigins = ["https://hermes.example.com"];
        maxIterations = 120;
        enableDashboard = true;
        profile = "test";
        memoryMax = "1G";
        cpuQuota = "100%";
      };

      # Don't actually start hermes — it would try to reach external services.
      systemd.services.hermes-agent.wantedBy = lib.mkForce [];
    };

    testScript = ''
      machine.wait_for_unit("multi-user.target")

      # User + group provisioned with UID/GID 10000
      uid = machine.succeed("id -u hermes").strip()
      gid = machine.succeed("id -g hermes").strip()
      assert uid == "10000", f"expected UID 10000, got {uid}"
      assert gid == "10000", f"expected GID 10000, got {gid}"

      # Unit file present
      machine.succeed("test -f /etc/systemd/system/hermes-agent.service")

      # Service config — env vars present
      unit = machine.succeed("systemctl cat hermes-agent")
      for key in [
        "HERMES_HOME=/var/lib/hermes-agent",
        "API_SERVER_PORT=8642",
        "API_SERVER_HOST=0.0.0.0",
        "WEBHOOK_PORT=8644",
        "HERMES_MAX_ITERATIONS=120",
        "API_SERVER_CORS_ORIGINS=https://hermes.example.com",
        "TELEGRAM_ALLOWED_USERS=42,7729797827",
        "TELEGRAM_ALLOWED_CHATS=-1001234567890",
        "HERMES_DASHBOARD=1",
        "HERMES_PROFILE=test",
      ]:
        assert key in unit, f"missing env: {key}"

      # Hardening directives present
      for directive in [
        "ProtectSystem=strict",
        "PrivateTmp=true",
        "NoNewPrivileges=true",
        "MemoryMax=1G",
        "CPUQuota=100%",
        "ProtectKernelTunables=true",
        "RestrictRealtime=true",
      ]:
        assert directive in unit, f"missing hardening: {directive}"

      # ReadWritePaths includes the dataDir
      assert "ReadWritePaths=/var/lib/hermes-agent" in unit, "ReadWritePaths missing dataDir"

      # ExecStart wrapper contains the bot-token bridge
      assert "TELEGRAM_BOT_TOKEN" in unit, "Telegram bot token bridge missing"
      assert "DISCORD_BOT_TOKEN" in unit, "Discord bot token bridge missing"
    '';
  };
}
