{
  pkgs,
  lib,
  settings ? {},
}: let
  yamlFormat = pkgs.formats.yaml {};

  # Battle-tested default config (homelab-tuned).
  # Values referencing ${VAR} are interpolated at hermes runtime from EnvironmentFile.
  defaultSettings = {
    model = {
      provider = "custom";
      default = "qwen-chat";
      base_url = "https://litellm.homelab.pastelariadev.com/v1";
      api_key = "\${OPENAI_API_KEY}";
      max_context = 262144;
    };

    auxiliary = {
      vision = {
        provider = "custom";
        model = "qwen-chat";
        base_url = "https://litellm.homelab.pastelariadev.com/v1";
        api_key = "\${OPENAI_API_KEY}";
      };
      compression = {
        provider = "custom";
        model = "qwen-chat";
        base_url = "https://litellm.homelab.pastelariadev.com/v1";
        api_key = "\${OPENAI_API_KEY}";
      };
      session_search = {
        provider = "custom";
        model = "qwen-chat";
        base_url = "https://litellm.homelab.pastelariadev.com/v1";
        api_key = "\${OPENAI_API_KEY}";
      };
    };

    compression = {
      enabled = true;
      threshold = 0.50;
      target_ratio = 0.20;
      protect_last_n = 20;
      protect_first_n = 3;
    };

    memory = {
      enabled = true;
      provider = "wiki";
      nudge_interval = 10;
      flush_min_turns = 6;
    };

    terminal = {
      backend = "local";
      timeout = 180;
      lifetime_seconds = 300;
    };

    # Platforms — port/secret/host typically come from env (gateway/config.py
    # injects env values into these blocks at runtime). Keep declarations here
    # so the platforms are registered + non-env settings persist.
    platforms = {
      api_server = {
        enabled = true;
      };
      webhook = {
        enabled = true;
        # Routes are config-only (env can't define routes). Each route MUST
        # have an HMAC secret. Example shape:
        #
        # extra:
        #   routes:
        #     ci:
        #       hmac_secret_env: WEBHOOK_CI_SECRET  # reads $WEBHOOK_CI_SECRET
        #       prompt: "CI event: {{ payload.action }} on {{ payload.repo }}"
      };
      telegram = {
        enabled = true;
        reply_to_mode = "first";
        guest_mode = false;
        extra = {
          disable_link_previews = false;
        };
      };
    };

    # Discord settings live at TOP LEVEL (not under platforms.discord) per
    # upstream schema.
    discord = {
      require_mention = true;
      auto_thread = true;
      free_response_channels = "";
      reactions = true;
      history_backfill = true;
      history_backfill_limit = 50;
    };

    agent = {
      max_turns = 60;
      verbose = false;
      reasoning_effort = "medium";
    };

    tool_loop_guardrails = {
      enabled = true;
    };

    session_reset = {
      enabled = true;
    };

    browser = {
      backend = "playwright";
    };

    delegation = {
      enabled = true;
    };

    skills = {
      creation_nudge_interval = 15;
    };

    file_read_max_chars = 100000;

    privacy = {
      redact_pii = true;
    };

    model_aliases = {
      qwen = {
        provider = "custom";
        model = "qwen-chat";
        base_url = "https://litellm.homelab.pastelariadev.com/v1";
        api_key = "\${OPENAI_API_KEY}";
      };
    };
  };

  merged = lib.recursiveUpdate defaultSettings settings;
in
  yamlFormat.generate "hermes-config.yaml" merged
