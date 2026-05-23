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

    # Gateway platform sections are informational here — runtime values come
    # from env vars (API_SERVER_*, WEBHOOK_*, HERMES_TELEGRAM_BOT_TOKEN, etc).
    gateway = {
      platforms = {
        api_server = {enabled = true;};
        webhook = {enabled = true;};
        telegram = {enabled = true;};
        discord = {enabled = true;};
      };
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
