{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  secrets,
  ...
}:

let
  socksPort = 1055;
  httpProxyPort = 1056;
  novncPorts = {
    from = 6080;
    to = 6099;
  };
  exitNode = "100.67.147.81";
  tailscale = config.services.tailscale.package;
  tsSocket = "/run/tailscale-browser/tailscaled.sock";

  images = import ./images.nix {
    inherit
      lib
      pkgs
      pkgs-unstable
      socksPort
      ;
  };

  compose = pkgs.writers.writeYAML "browser-compose.yml" {
    services = {
      browser = {
        image = "browser-chromium:latest";
        pull_policy = "never";
        restart = "unless-stopped";
        shm_size = "1gb";
        tmpfs = [ "/tmp" ];
        # Docker's seccomp profile blocks user namespaces without it, which
        # Chromium's sandbox needs. browser-start drops all caps before Chromium.
        cap_add = [ "SYS_ADMIN" ];
        ports = [ "\${NOVNC_PORT:?set NOVNC_PORT in .env}:6080" ];
        volumes = [
          "./profile:/data/profile"
          "./files:/files"
        ];
      };
      agent = {
        image = "browser-agent:latest";
        pull_policy = "never";
        restart = "unless-stopped";
        network_mode = "service:browser";
        environment = {
          NOVNC_URL = "http://${config.networking.hostName}:\${NOVNC_PORT}/vnc.html";
          HTTPS_PROXY = "http://10.0.2.2:${toString httpProxyPort}";
          HTTP_PROXY = "http://10.0.2.2:${toString httpProxyPort}";
          NO_PROXY = "127.0.0.1,localhost";
        };
        volumes = [
          "./work:/work"
          "./files:/files"
          "./claude-home:/root"
        ];
      };
    };
  };

  browserDocker = pkgs.writeShellScriptBin "browser-docker" ''
    uid=$(id -u browser)
    cd /
    exec sudo -u browser env \
      XDG_RUNTIME_DIR=/run/user/$uid \
      DOCKER_HOST=unix:///run/user/$uid/docker.sock \
      ${pkgs.docker}/bin/docker "$@"
  '';

  browserClaude = pkgs.writeShellScriptBin "browser-claude" ''
    name=$1
    if [ -z "$name" ]; then
      echo "usage: browser-claude <name> [claude args]" >&2
      echo "projects: $(sudo -u browser ls /srv/browser | tr '\n' ' ')" >&2
      exit 1
    fi
    shift
    [[ $name =~ ^[a-z0-9][a-z0-9_-]*$ ]] || { echo "name must match [a-z0-9][a-z0-9_-]*" >&2; exit 1; }
    dir=/srv/browser/$name
    if ! sudo -u browser test -f "$dir/.env"; then
      used=$(sudo -u browser sh -c 'cat /srv/browser/*/.env 2>/dev/null' | sed -n 's/^NOVNC_PORT=//p')
      port=
      for p in $(seq ${toString novncPorts.from} ${toString novncPorts.to}); do
        grep -qx "$p" <<<"$used" || { port=$p; break; }
      done
      [ -n "$port" ] || { echo "no free port in ${toString novncPorts.from}-${toString novncPorts.to}" >&2; exit 1; }
      read -rp "create project $name on port $port? [y/N] " answer
      [ "$answer" = y ] || exit 1
      sudo -u browser install -d -m 2770 "$dir" "$dir"/{work,files,files/downloads,profile,claude-home}
      echo "NOVNC_PORT=$port" | sudo -u browser tee "$dir/.env" >/dev/null
    fi
    dc() { ${lib.getExe browserDocker} compose -f ${compose} --project-directory "$dir" -p "browser-$name" "$@"; }
    dc up -d --quiet-pull
    dc exec -it agent claude --permission-mode auto "$@"
  '';
in
{
  users.users.browser = {
    isSystemUser = true;
    uid = 985;
    group = "browser";
    home = "/var/lib/browser";
    createHome = true;
    linger = true;
    autoSubUidGidRange = true;
  };
  users.groups.browser = { };
  users.users.petrtsopa.extraGroups = [ "browser" ];

  virtualisation.docker.rootless = {
    enable = true;
    extraPackages = [ pkgs.passt ];
  };
  systemd.user.services.docker.environment = {
    DOCKERD_ROOTLESS_ROOTLESSKIT_NET = "pasta";
    DOCKERD_ROOTLESS_ROOTLESSKIT_PORT_DRIVER = "implicit";
    DOCKERD_ROOTLESS_ROOTLESSKIT_DISABLE_HOST_LOOPBACK = "false";
  };

  systemd.tmpfiles.rules = [ "d /srv/browser 2770 browser browser -" ];

  systemd.services.browser-images = {
    wantedBy = [ "multi-user.target" ];
    wants = [ "user@${toString config.users.users.browser.uid}.service" ];
    after = [ "user@${toString config.users.users.browser.uid}.service" ];
    path = [ pkgs.docker ];
    script = ''
      export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock
      until docker info >/dev/null 2>&1; do sleep 1; done
      ${images.browser} | docker load
      ${images.agent} | docker load
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "browser";
      TimeoutStartSec = 600;
    };
  };

  # Rootless containers egress as the browser uid. Allow only the exit-node
  # proxies; pasta would otherwise expose host loopback and the tailnet.
  networking.firewall.extraCommands = ''
    ip46tables -w -D OUTPUT -m owner --uid-owner browser -j browser-out 2>/dev/null || true
    ip46tables -w -F browser-out 2>/dev/null || ip46tables -w -N browser-out
    ip46tables -w -A browser-out -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
    iptables -w -A browser-out -d 127.0.0.1 -p tcp -m multiport --dports ${toString socksPort},${toString httpProxyPort} -j RETURN
    ip46tables -w -A browser-out -j REJECT
    ip46tables -w -I OUTPUT -m owner --uid-owner browser -j browser-out
  '';
  networking.firewall.extraStopCommands = ''
    ip46tables -w -D OUTPUT -m owner --uid-owner browser -j browser-out 2>/dev/null || true
  '';

  networking.firewall.interfaces.tailscale0.allowedTCPPortRanges = [ novncPorts ];

  age.secrets.tailscale-browser-authkey.file = secrets + "/tailscale-browser-authkey.age";

  systemd.services.tailscaled-browser = {
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      DynamicUser = true;
      StateDirectory = "tailscale-browser";
      RuntimeDirectory = "tailscale-browser";
      LoadCredential = "authkey:${config.age.secrets.tailscale-browser-authkey.path}";
      ExecStart = "${tailscale}/bin/tailscaled --tun=userspace-networking --socks5-server=127.0.0.1:${toString socksPort} --outbound-http-proxy-listen=127.0.0.1:${toString httpProxyPort} --statedir=/var/lib/tailscale-browser --socket=${tsSocket} --port=0";
      ExecStartPost = pkgs.writeShellScript "tailscale-browser-up" ''
        while [ ! -S ${tsSocket} ]; do sleep 0.2; done
        ${tailscale}/bin/tailscale --socket=${tsSocket} up \
          --auth-key=file:$CREDENTIALS_DIRECTORY/authkey \
          --hostname=potato-browser \
          --advertise-tags=tag:browser \
          --exit-node=${exitNode}
      '';
      Restart = "on-failure";
    };
  };

  environment.systemPackages = [
    browserDocker
    browserClaude
  ];

  backup.locations.browser = {
    from = [
      "/srv/browser"
    ];
  };
}
