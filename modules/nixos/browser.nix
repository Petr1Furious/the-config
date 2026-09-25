{
  config,
  pkgs,
  pkgs-unstable,
  ...
}:

let
  displayNum = 1;
  vncPort = 5901;
  cdpPort = 9222;
  webPort = 6080;
  socksPort = 1055;
  width = 1600;
  height = 1000;
  exitNode = "100.67.147.81";
  tailscale = config.services.tailscale.package;
  tsSocket = "/run/tailscale-browser/tailscaled.sock";
in
{
  systemd.services.tailscaled-browser = {
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      DynamicUser = true;
      StateDirectory = "tailscale-browser";
      RuntimeDirectory = "tailscale-browser";
      LoadCredential = "authkey:${config.age.secrets.tailscale-authkey.path}";
      ExecStart = "${tailscale}/bin/tailscaled --tun=userspace-networking --socks5-server=127.0.0.1:${toString socksPort} --statedir=/var/lib/tailscale-browser --socket=${tsSocket} --port=0";
      ExecStartPost = pkgs.writeShellScript "tailscale-browser-up" ''
        while [ ! -S ${tsSocket} ]; do sleep 0.2; done
        ${tailscale}/bin/tailscale --socket=${tsSocket} up \
          --auth-key=file:$CREDENTIALS_DIRECTORY/authkey \
          --hostname=potato-browser \
          --advertise-tags=tag:server \
          --exit-node=${exitNode}
      '';
      Restart = "on-failure";
    };
  };

  systemd.services.browser = {
    wantedBy = [ "multi-user.target" ];
    wants = [ "tailscaled-browser.service" ];
    after = [ "tailscaled-browser.service" ];
    environment = {
      DISPLAY = ":${toString displayNum}";
      TZ = "Europe/Copenhagen";
    };
    script = ''
      ${pkgs.tigervnc}/bin/Xvnc :${toString displayNum} -localhost -rfbport ${toString vncPort} \
        -SecurityTypes None -geometry ${toString width}x${toString height} &
      while [ ! -S /tmp/.X11-unix/X${toString displayNum} ]; do sleep 0.2; done

      exec ${pkgs.chromium}/bin/chromium \
        --user-data-dir=/home/petrtsopa/browser/chrome \
        --remote-debugging-port=${toString cdpPort} \
        --proxy-server=socks5://127.0.0.1:${toString socksPort} \
        --no-first-run \
        --window-position=0,0 \
        --window-size=${toString width},${toString height}
    '';
    serviceConfig = {
      User = "petrtsopa";
      Restart = "always";
      RestartSec = 1;
    };
  };

  systemd.services.browser-vnc = {
    wantedBy = [ "multi-user.target" ];
    after = [ "browser.service" ];
    serviceConfig = {
      User = "petrtsopa";
      ExecStart = "${pkgs.python3Packages.websockify}/bin/websockify --web ${pkgs.novnc}/share/webapps/novnc ${toString webPort} 127.0.0.1:${toString vncPort}";
      Restart = "on-failure";
    };
  };

  programs.chromium = {
    enable = true;
    extraOpts.WebRtcIPHandling = "disable_non_proxied_udp";
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ webPort ];

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji
  ];

  environment.systemPackages = [ pkgs-unstable.playwright-mcp ];
}
