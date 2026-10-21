{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:

let
  cfg = config.claude;
  jsonFormat = pkgs.formats.json { };

  rustAnalyzer = pkgs.writeShellScript "rust-analyzer" ''
    export PATH="$PATH:${
      lib.makeBinPath [
        pkgs-unstable.cargo
        pkgs-unstable.rustc
      ]
    }"
    exec ${lib.getExe pkgs-unstable.rust-analyzer} "$@"
  '';

  powerlineSegments = [
    {
      model.enabled = true;
    }
    {
      thinking = {
        enabled = true;
        showEnabled = false;
      };
    }
    {
      context = {
        enabled = true;
        percentageMode = "used";
      };
    }
    {
      block = {
        enabled = true;
        showPace = true;
      };
    }
    {
      weekly = {
        enabled = true;
        showPace = true;
      };
    }
    {
      session = {
        enabled = true;
        type = "cost";
        costSource = "official";
      };
    }
    {
      today = {
        enabled = true;
        type = "cost";
      };
    }
    {
      cacheTimer = {
        enabled = true;
        displayMode = "remaining";
      };
    }
    {
      directory = {
        enabled = true;
        style = "fish";
      };
    }
    {
      git = {
        enabled = true;
        showSha = false;
        showWorkingTree = true;
      };
    }
    {
      metrics = {
        enabled = true;
        showResponseTime = false;
        showDuration = false;
        showMessageCount = false;
      };
    }
  ];

  powerlineConfig = pkgs.writeText "claude-powerline.json" ''
    {
      "theme": "dark",
      "display": {
        "style": "powerline",
        "charset": "unicode",
        "lines": [{"segments": {${
          lib.concatMapStringsSep ", " (
            s:
            lib.concatStringsSep ", " (
              lib.mapAttrsToList (n: v: "${builtins.toJSON n}: ${builtins.toJSON v}") s
            )
          ) powerlineSegments
        }}}]
      },
      "budget": {"today": {"amount": 0}}
    }
  '';

  settingsFile = jsonFormat.generate "claude-code-settings.json" cfg.settings;
in
{
  options.claude = {
    grafanaTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

    settings = lib.mkOption {
      inherit (jsonFormat) type;
      default = { };
      description = ''
        Merged into ~/.claude/settings.json on activation. Declared values,
        lists included, replace what is in the file; everything else is kept.
      '';
    };

    github.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    playwright.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };

  config = {
    programs.claude-code = {
      enable = true;
      package = pkgs-unstable.claude-code;
      context = ./claude/CLAUDE.md;
      skills = lib.genAttrs [
        "design"
        "own"
        "explain"
        "teach"
      ] (name: ./claude/skills/${name}.md);

      mcpServers = {
        nixos = {
          command = lib.getExe pkgs-unstable.mcp-nixos;
        };
        context7 = {
          type = "http";
          url = "https://mcp.context7.com/mcp";
        };
      }
      // lib.optionalAttrs config.programs.atuin.enable {
        atuin = {
          command = lib.getExe config.programs.atuin.package;
          args = [ "mcp" ];
        };
      }
      // lib.optionalAttrs cfg.github.enable {
        github = {
          type = "http";
          url = "https://api.githubcopilot.com/mcp/";
          headers.X-MCP-Readonly = "true";
          headersHelper = "${pkgs.writeShellScript "github-mcp-headers" ''
            token="$(${lib.getExe pkgs.gh} auth token)" || exit 1
            ${lib.getExe pkgs.jq} -n --arg token "$token" '{Authorization: ("Bearer " + $token)}'
          ''}";
        };
      }
      // lib.optionalAttrs (cfg.grafanaTokenFile != null) {
        grafana = {
          command = "${pkgs.writeShellScript "grafana-mcp" ''
            GRAFANA_SERVICE_ACCOUNT_TOKEN="$(< "${cfg.grafanaTokenFile}")" \
              exec ${lib.getExe pkgs-unstable.mcp-grafana} -disable-write
          ''}";
          env.GRAFANA_URL = "https://grafana.petr1furious.me";
        };
      }
      // lib.optionalAttrs cfg.playwright.enable {
        playwright = {
          command = lib.getExe pkgs-unstable.playwright-mcp;
          args = lib.optional pkgs.stdenv.hostPlatform.isLinux "--headless";
        };
      };

      lspServers = {
        nix = {
          command = lib.getExe pkgs-unstable.nixd;
          extensionToLanguage.".nix" = "nix";
        };
        rust = {
          command = "${rustAnalyzer}";
          extensionToLanguage.".rs" = "rust";
        };
        java = {
          command = lib.getExe pkgs-unstable.jdt-language-server;
          extensionToLanguage.".java" = "java";
        };
      };
    };

    claude.settings = {
      env.DISABLE_AUTOUPDATER = "1";

      permissions = {
        defaultMode = "auto";
        allow = [ ];
        deny = [
          "Read(~/.ssh/**)"
          "Read(~/.claude/.credentials.json)"
          "Read(~/.config/gh/hosts.yml)"
          "Read(//run/agenix/**)"
          "Read(//run/agenix.d/**)"
        ];
      };

      statusLine = {
        type = "command";
        command = "${lib.getExe pkgs-unstable.claude-powerline} --config=${powerlineConfig}";
        padding = 0;
        refreshInterval = 30;
      };
    };

    home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings="${config.programs.claude-code.configDir}/settings.json"
      run mkdir -p "$(dirname "$settings")"
      [ -L "$settings" ] && run rm "$settings"
      [ -f "$settings" ] || echo '{}' > "$settings"
      tmp="$(mktemp "$settings.XXXXXX")"
      ${lib.getExe pkgs.jq} --slurpfile nix ${settingsFile} '
        . * $nix[0]
      ' "$settings" > "$tmp"
      run mv "$tmp" "$settings"
      rm -f "$tmp"
    '';
  };
}
