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

  statusLine = pkgs.writeShellApplication {
    name = "claude-statusline";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.jq
    ];
    text = builtins.readFile ./claude/statusline.sh;
  };

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
        command = lib.getExe statusLine;
        padding = 0;
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
