{
  pkgs,
  pkgs-unstable,
  ...
}:

let
  displayNum = 1;
  vncPort = 5901;
  cdpPort = 9222;
  webPort = 6080;
  width = 1600;
  height = 1000;
in
{
  systemd.services.browser = {
    wantedBy = [ "multi-user.target" ];
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

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ webPort ];

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji
  ];

  environment.systemPackages = [ pkgs-unstable.playwright-mcp ];
}
