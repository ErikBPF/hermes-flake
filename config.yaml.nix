{
  pkgs,
  lib,
  settings ? {},
}: let
  yamlFormat = pkgs.formats.yaml {};

  # Battle-tested default config matching Erik's homelab production hermes
  # (Discovery host). Values referencing ${VAR} are interpolated at hermes
  # runtime from EnvironmentFile.
  defaultSettings = {
    model = {
      provider = "custom";
      default = "qwen-chat";
      base_url = "https://litellm.homelab.pastelariadev.com/v1";
      api_key = "\${OPENAI_API_KEY}";
      max_context = 262144;
    };

    # Auxiliary model routing — vision / compression / session_search.
    # All target the same LiteLLM endpoint as the primary model.
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

    # Named model aliases — let `hermes --model qwen ...` resolve.
    model_aliases = {
      qwen = {
        model = "qwen-chat";
        provider = "custom";
        base_url = "https://litellm.homelab.pastelariadev.com/v1";
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

    display = {
      theme = "dark";
    };

    agent = {
      max_turns = 60;
      verbose = false;
      reasoning_effort = "medium";
    };

    tool_loop_guardrails = {
      warnings_enabled = true;
      hard_stop_enabled = false;
      warn_after = {
        exact_failure = 2;
        same_tool_failure = 3;
        idempotent_no_progress = 2;
      };
      hard_stop_after = {
        exact_failure = 5;
        same_tool_failure = 8;
        idempotent_no_progress = 5;
      };
    };

    session_reset = {
      mode = "both";
      idle_minutes = 1440;
      at_hour = 4;
      group_sessions_per_user = true;
    };

    browser = {
      inactivity_timeout = 120;
    };

    delegation = {
      max_iterations = 50;
      max_concurrent_children = 3;
      max_spawn_depth = 1;
    };

    skills = {
      creation_nudge_interval = 15;
    };

    stt = {
      enabled = true;
      provider = "local";
      local = {
        model = "base";
      };
    };

    file_read_max_chars = 100000;

    privacy = {
      redact_pii = true;
    };

    # Platform registration — runtime port/secret/host values flow from env
    # vars via gateway/config.py.
    platforms = {
      api_server = {
        enabled = true;
      };
      webhook = {
        enabled = true;
        # Routes go here (config-only, can't be set via env). See
        # docs/WEBHOOK_ROUTES.md.
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

    # Discord — TOP-LEVEL per upstream schema (NOT under platforms.discord).
    discord = {
      require_mention = true;
      auto_thread = true;
      free_response_channels = "";
      reactions = true;
      history_backfill = true;
      history_backfill_limit = 50;
    };
  };

  merged = lib.recursiveUpdate defaultSettings settings;
in
  yamlFormat.generate "hermes-config.yaml" merged
