{
  lib,
  pkgs,
  pkgs-unstable,
  socksPort,
}:

let
  width = 1600;
  height = 1000;
  inherit (pkgs) dockerTools;

  base = with pkgs; [
    bashInteractive
    coreutils
    dockerTools.binSh
    dockerTools.usrBinEnv
    dockerTools.caCertificates
    dockerTools.fakeNss
  ];

  tmp = "mkdir -m 1777 tmp";

  chromiumPolicy = pkgs.writeTextDir "etc/chromium/policies/managed/browser.json" (
    builtins.toJSON {
      DownloadDirectory = "/files/downloads";
      WebRtcIPHandling = "disable_non_proxied_udp";
    }
  );

  # Rootless Docker's pasta maps the host's loopback to the gateway address.
  browserRun = pkgs.writeShellScript "browser-run" ''
    mkdir -p $HOME
    ${pkgs.tigervnc}/bin/Xvnc :1 -localhost -rfbport 5901 \
      -SecurityTypes None -geometry ${toString width}x${toString height} &
    while [ ! -S /tmp/.X11-unix/X1 ]; do sleep 0.2; done
    ${pkgs.python3Packages.websockify}/bin/websockify \
      --web ${pkgs.novnc}/share/webapps/novnc 6080 127.0.0.1:5901 &

    exec ${pkgs.chromium}/bin/chromium \
      --user-data-dir=/data/profile \
      --remote-debugging-port=9222 \
      --proxy-server=socks5://10.0.2.2:${toString socksPort} \
      --no-first-run \
      --window-position=0,0 \
      --window-size=${toString width},${toString height}
  '';

  # Chromium refuses to sandbox itself as root, so drop to an unprivileged uid
  # with no capabilities after handing it the profile and downloads.
  browserStart = pkgs.writeShellScript "browser-start" ''
    rm -f /data/profile/Singleton{Lock,Cookie,Socket}
    mkdir -p /files/downloads
    mkdir -m 1777 -p /tmp/.X11-unix
    chown -R 1000:1000 /data/profile /files/downloads
    exec ${pkgs.util-linux}/bin/setpriv --reuid=1000 --regid=1000 --clear-groups \
      --inh-caps=-all --bounding-set=-all ${browserRun}
  '';

  claudeConfig = pkgs.runCommand "claude-config" { } ''
    mkdir -p $out/etc/claude/skills/browser $out/etc/claude-code
    cp ${../../../home/claude/CLAUDE.md} $out/etc/claude/CLAUDE.md
    cp ${./skill.md} $out/etc/claude/skills/browser/SKILL.md
    cp ${
      pkgs.writeText "managed-mcp.json" (
        builtins.toJSON {
          mcpServers.playwright = {
            # 0.0.83 (unstable) attaches over CDP in a fresh empty context instead
            # of the profile's, so logins made in its window vanish with the session.
            command = lib.getExe pkgs.playwright-mcp;
            args = [
              "--cdp-endpoint"
              "http://127.0.0.1:9222"
              "--output-dir"
              "/work/output"
            ];
          };
        }
      )
    } $out/etc/claude-code/managed-mcp.json
  '';

  agentStart = pkgs.writeShellScript "agent-start" ''
    mkdir -p /root/.claude/skills
    ln -sfn /etc/claude/CLAUDE.md /root/.claude/CLAUDE.md
    ln -sfn /etc/claude/skills/browser /root/.claude/skills/browser
    exec sleep infinity
  '';
in
{
  browser = dockerTools.streamLayeredImage {
    name = "browser-chromium";
    tag = "latest";
    contents = base ++ [ chromiumPolicy ];
    fakeRootCommands = tmp;
    config = {
      Cmd = [ browserStart ];
      Env = [
        "DISPLAY=:1"
        "HOME=/tmp/home"
        "TZ=Europe/Copenhagen"
        "TZDIR=${pkgs.tzdata}/share/zoneinfo"
        "FONTCONFIG_FILE=${
          pkgs.makeFontsConf {
            fontDirectories = with pkgs; [
              noto-fonts
              noto-fonts-color-emoji
            ];
          }
        }"
      ];
    };
  };

  agent = dockerTools.streamLayeredImage {
    name = "browser-agent";
    tag = "latest";
    contents =
      base
      ++ [ claudeConfig ]
      ++ (with pkgs; [
        curl
        diffutils
        findutils
        gawk
        git
        gnugrep
        gnused
        jq
        less
        procps
        ripgrep
        which
        pkgs-unstable.claude-code
      ]);
    fakeRootCommands = tmp;
    config = {
      Cmd = [ agentStart ];
      WorkingDir = "/work";
      Env = [
        "HOME=/root"
        "SHELL=/bin/bash"
        "DISABLE_AUTOUPDATER=1"
        "TZ=Europe/Copenhagen"
        "TZDIR=${pkgs.tzdata}/share/zoneinfo"
      ];
    };
  };
}
