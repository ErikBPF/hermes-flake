# Example: official-image hermes-agent wired to a LiteLLM gateway.
#
# Shows the upstream-adherent production path — services.hermes-agent-oci runs
# the vendor image, while Nix renders config.yaml from `settings` and mounts it
# read-only into /opt/data. Every model call (chat, vision, STT/TTS,
# compression, embeddings) speaks OpenAI to ONE LiteLLM proxy; routes/keys/
# budgets live there, never here.
#
# Apply: import this module on a host that already has sops-nix + a docker (or
# podman) backend, then point `litellmUrl` at your proxy.
{
  config,
  lib,
  ...
}: let
  # The single sanctioned egress. Everything below routes here.
  litellmUrl = "https://litellm.example.com/v1";
in {
  imports = [
    # inputs.hermes-flake.nixosModules.hermes-agent-oci
  ];

  # sops secret carrying upstream-BARE names: OPENAI_API_KEY (the LiteLLM
  # virtual key), API_SERVER_KEY, TELEGRAM_BOT_TOKEN, DISCORD_BOT_TOKEN, ...
  sops.secrets."hermes-agent/env" = {
    sopsFile = ./secrets/hermes.env.sops;
    format = "dotenv";
    mode = "0440";
    owner = "10000"; # image drops to UID 10000
  };

  services.hermes-agent-oci = {
    enable = true;
    backend = "docker";

    # PIN for production — a digest is the only fully reproducible form.
    image = "nousresearch/hermes-agent:latest";

    openBindAddress = "0.0.0.0"; # behind a reverse proxy; API_SERVER_KEY required
    openaiBaseUrl = litellmUrl;
    environmentFile = config.sops.secrets."hermes-agent/env".path;
    telegramAllowedUsers = [123456789];

    # YOLO: auto-approve non-catastrophic commands declaratively. hermes' own
    # hardcoded floor (rm -rf /, mkfs, shutdown, …) still blocks regardless.
    extraEnvironment.HERMES_YOLO_MODE = "1";

    # ── Providers / models — rendered into /opt/data/config.yaml ───────────
    settings = {
      # Primary chat brain: GLM-5.2 via LiteLLM (flat-rate opencode Go).
      model = {
        provider = "custom";
        default = "glm-5";
        base_url = litellmUrl;
        api_key = "\${OPENAI_API_KEY}";
        # `context_length` (upstream v2026.6.19); must match the served context
        # on the model host. `max_context` is silently ignored.
        context_length = 196608;
      };

      # Switchable coding/heavy models — flat-rate opencode Go routes exposed
      # on the proxy. Pick at runtime with `/model kimi-k2-code` etc. Default
      # stays local qwen-chat so casual turns never touch the shared budget.
      model_aliases = {
        qwen = {
          model = "qwen-chat";
          provider = "custom";
          base_url = litellmUrl;
        };
        kimi = {
          model = "kimi-k2-code";
          provider = "custom";
          base_url = litellmUrl;
        };
        glm = {
          model = "glm-5";
          provider = "custom";
          base_url = litellmUrl;
        };
        qwen-max = {
          model = "qwen3-max";
          provider = "custom";
          base_url = litellmUrl;
        };
        minimax = {
          model = "minimax-m2";
          provider = "custom";
          base_url = litellmUrl;
        };
        mimo = {
          model = "mimo";
          provider = "custom";
          base_url = litellmUrl;
        };
        mimo-pro = {
          model = "mimo-pro";
          provider = "custom";
          base_url = litellmUrl;
        };
      };

      # Auxiliary models — all through the same proxy.
      auxiliary = let
        route = model: {
          inherit model;
          provider = "custom";
          base_url = litellmUrl;
          api_key = "\${OPENAI_API_KEY}";
        };
      in {
        vision = route "vision-qwen2vl";
        # MiMo V2.5 — free, 24/7 cloud (vs qwen-chat which sleeps with Orion).
        compression = route "mimo";
        session_search = route "mimo";
        transcription = route "whisper-pt-br";
        tts = route "tts-pt-br";
        embeddings = route "embeddings-qwen3";
      };

      agent.max_turns = 60;
      approvals.mode = "off"; # permanent declarative auto-approve (see above)
    };

    soulFile = ./homelab-SOUL.md;
  };
}
