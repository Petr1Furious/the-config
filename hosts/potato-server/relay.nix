{ config, lib, pkgs, ... }:

# Client side of the transparent relay. The Selectel host (82.148.28.127) DNATs
# all its ports to this host over the WireGuard tunnel below, preserving the
# original client source IPs. This host must therefore:
#   - accept relayed packets whose source is an arbitrary public client IP
#     (checkReversePath = "loose", otherwise strict rp_filter drops them), and
#   - send replies for src 10.99.0.2 back through the tunnel (policy routing),
#     while leaving this host's own default route / egress untouched.
# See scripts/relay-setup.sh and hosts/potato-server/default.nix.

let
  relayHost = "82.148.28.127";
  relayEndpoint = "${relayHost}:51820";
  selectelPubKey = "T9YQizWRyzmPnG1343AxK8ad82MM0L6g5abrsSp2QXk="; # from relay-setup.sh phase 1
  wgSelf = "10.99.0.2";
  tunTable = 100;
  wgPort = 51820; # WireGuard endpoint port — must NOT be hairpinned (keeps the tunnel up)
  mgmtSshPort = 2222; # Selectel's own sshd — leave reachable directly
in
{
  networking.wireguard.interfaces.wg0 = {
    ips = [ "${wgSelf}/30" ];
    mtu = 1420;
    privateKeyFile = "/var/lib/wireguard/wg0.key";
    generatePrivateKeyFile = true;
    # clients have arbitrary source IPs (allowedIPs 0.0.0.0/0), but we must NOT
    # let wireguard hijack the default route — routing is done manually below.
    allowedIPsAsRoutes = false;

    peers = [
      {
        publicKey = selectelPubKey;
        endpoint = relayEndpoint;
        allowedIPs = [ "0.0.0.0/0" ];
        persistentKeepalive = 25;
      }
    ];

    # Only traffic whose *source* is the tunnel address is sent back over the
    # tunnel; everything else this host originates uses the normal default route.
    #
    # NAT hairpin: this host's own public services resolve to the relay IP. A
    # packet sent there would come back over the tunnel with this host's own
    # public IP as source and never complete (the un-DNAT only exists on the
    # relay). So redirect our own outbound traffic to the relay IP straight to
    # the local tunnel address instead — except the WireGuard port (would break
    # the tunnel) and the relay's own management SSH port.
    postSetup = ''
      ${pkgs.iproute2}/bin/ip rule add from ${wgSelf} table ${toString tunTable} priority 100 || true
      ${pkgs.iproute2}/bin/ip route replace default dev wg0 table ${toString tunTable}
      ${pkgs.iptables}/bin/iptables -t nat -C OUTPUT -d ${relayHost} -p tcp -m tcp ! --dport ${toString mgmtSshPort} -j DNAT --to-destination ${wgSelf} 2>/dev/null \
        || ${pkgs.iptables}/bin/iptables -t nat -A OUTPUT -d ${relayHost} -p tcp -m tcp ! --dport ${toString mgmtSshPort} -j DNAT --to-destination ${wgSelf}
      ${pkgs.iptables}/bin/iptables -t nat -C OUTPUT -d ${relayHost} -p udp -m udp ! --dport ${toString wgPort} -j DNAT --to-destination ${wgSelf} 2>/dev/null \
        || ${pkgs.iptables}/bin/iptables -t nat -A OUTPUT -d ${relayHost} -p udp -m udp ! --dport ${toString wgPort} -j DNAT --to-destination ${wgSelf}
    '';
    postShutdown = ''
      ${pkgs.iproute2}/bin/ip rule del from ${wgSelf} table ${toString tunTable} priority 100 || true
      ${pkgs.iproute2}/bin/ip route flush table ${toString tunTable} || true
      ${pkgs.iptables}/bin/iptables -t nat -D OUTPUT -d ${relayHost} -p tcp -m tcp ! --dport ${toString mgmtSshPort} -j DNAT --to-destination ${wgSelf} 2>/dev/null || true
      ${pkgs.iptables}/bin/iptables -t nat -D OUTPUT -d ${relayHost} -p udp -m udp ! --dport ${toString wgPort} -j DNAT --to-destination ${wgSelf} 2>/dev/null || true
    '';
  };

  # Relayed packets arrive on wg0 with public client source IPs whose route is
  # via eth0, not wg0 — strict reverse-path filtering would drop them.
  networking.firewall.checkReversePath = "loose";
}
