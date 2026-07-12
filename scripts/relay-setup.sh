#!/usr/bin/env bash
#
# relay-setup.sh — turn the Selectel host into a transparent TCP/UDP relay to OVH.
#
# The OVH host is DPI-blocked from Russia; the Selectel host is not and can reach
# OVH freely. This script sets up a WireGuard tunnel Selectel<->OVH and DNATs all
# ports arriving on the Selectel public IP to OVH over the tunnel, WITHOUT source
# NAT, so the OVH host sees the real client IPs (fully transparent).
#
# Runs from the local machine over SSH. Idempotent — safe to re-run.
#
# Usage:
#   ./relay-setup.sh                       # phase 1: install + generate keys, print Selectel pubkey
#   OVH_PUBKEY=<key> ./relay-setup.sh      # phase 2: sshd->2222, wireguard, DNAT relay
#
set -euo pipefail

# --- config ---------------------------------------------------------------
RELAY_HOST="82.148.28.127"      # Selectel (this becomes the relay)
RELAY_SSH="root@${RELAY_HOST}"
RELAY_IFACE="eth0"              # Selectel public interface
TARGET_HOST="217.182.203.68"    # OVH (traffic is forwarded here) — informational

WG_PORT="51820"                 # WireGuard UDP port on Selectel
MGMT_SSH_PORT="2222"            # Selectel's own sshd (excluded from DNAT)
RELAY_WG_IP="10.99.0.1"         # Selectel tunnel IP
TARGET_WG_IP="10.99.0.2"        # OVH tunnel IP
WG_MTU="1420"

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10)
# -------------------------------------------------------------------------

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
err() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; }

rsh() { ssh "${SSH_OPTS[@]}" "$RELAY_SSH" "$@"; }

# Run a script (on stdin) on the relay as root. Any VAR=value arguments are
# exported into the remote shell first (ssh does not forward local env).
rsh_script() {
  local exports="" kv body
  for kv in "$@"; do
    exports+="export ${kv%%=*}=$(printf '%q' "${kv#*=}")"$'\n'
  done
  body="$(cat)"
  printf '%s\n%s\n' "$exports" "$body" | ssh "${SSH_OPTS[@]}" "$RELAY_SSH" 'bash -s'
}

# ==========================================================================
# Phase 1: install packages, generate WireGuard keypair, print public key.
# ==========================================================================
phase1() {
  log "Phase 1: installing packages and generating keys on ${RELAY_HOST}"
  rsh_script <<'REMOTE'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if ! dpkg -s wireguard-tools >/dev/null 2>&1 || ! dpkg -s nftables >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq wireguard-tools nftables
fi

install -d -m 0700 /etc/wireguard
if [[ ! -s /etc/wireguard/privatekey ]]; then
  umask 077
  wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey
fi
chmod 600 /etc/wireguard/privatekey
echo "SELECTEL_PUBKEY=$(cat /etc/wireguard/publickey)"
REMOTE
}

# ==========================================================================
# Phase 2: sshd on 2222, ip_forward, WireGuard, DNAT relay.
# ==========================================================================
phase2() {
  if [[ -z "${OVH_PUBKEY:-}" ]]; then
    err "OVH_PUBKEY is required for phase 2"; exit 1
  fi
  log "Phase 2: configuring relay on ${RELAY_HOST} (target OVH pubkey: ${OVH_PUBKEY})"

  # --- 2.1 make sshd listen on 2222 in addition to 22 (socket-activated) ---
  log "2.1 adding sshd listener on port ${MGMT_SSH_PORT} (keeping 22 as fallback)"
  rsh_script "MGMT_SSH_PORT=$MGMT_SSH_PORT" <<'REMOTE'
set -euo pipefail
: "${MGMT_SSH_PORT:?}"
install -d -m 0755 /etc/systemd/system/ssh.socket.d
cat > /etc/systemd/system/ssh.socket.d/override.conf <<EOF
[Socket]
ListenStream=
ListenStream=0.0.0.0:22
ListenStream=[::]:22
ListenStream=0.0.0.0:${MGMT_SSH_PORT}
ListenStream=[::]:${MGMT_SSH_PORT}
EOF
systemctl daemon-reload
systemctl restart ssh.socket
systemctl --no-pager is-active ssh.socket
ss -tlnp | grep -E ":(22|${MGMT_SSH_PORT})\b" || true
REMOTE

  # verify the new management port works from here BEFORE touching routing
  log "2.1 verifying ssh on port ${MGMT_SSH_PORT} works from this machine"
  if ! ssh "${SSH_OPTS[@]}" -p "$MGMT_SSH_PORT" "$RELAY_SSH" true; then
    err "Cannot reach ${RELAY_HOST}:${MGMT_SSH_PORT} — aborting before DNAT to avoid lockout"
    exit 1
  fi
  log "2.1 OK: ssh -p ${MGMT_SSH_PORT} works"

  # --- 2.2 enable IP forwarding ---
  log "2.2 enabling net.ipv4.ip_forward"
  rsh_script <<'REMOTE'
set -euo pipefail
cat > /etc/sysctl.d/99-ovhproxy.conf <<EOF
net.ipv4.ip_forward = 1
EOF
sysctl -p /etc/sysctl.d/99-ovhproxy.conf >/dev/null
REMOTE

  # --- 2.3 WireGuard interface ---
  log "2.3 writing WireGuard config and bringing up wg0"
  rsh_script "OVH_PUBKEY=$OVH_PUBKEY" "WG_PORT=$WG_PORT" "WG_MTU=$WG_MTU" \
    "RELAY_WG_IP=$RELAY_WG_IP" "TARGET_WG_IP=$TARGET_WG_IP" <<'REMOTE'
set -euo pipefail
: "${OVH_PUBKEY:?}" "${WG_PORT:?}" "${WG_MTU:?}" "${RELAY_WG_IP:?}" "${TARGET_WG_IP:?}"
umask 077
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = ${RELAY_WG_IP}/30
ListenPort = ${WG_PORT}
PrivateKey = $(cat /etc/wireguard/privatekey)
MTU = ${WG_MTU}

[Peer]
PublicKey = ${OVH_PUBKEY}
AllowedIPs = ${TARGET_WG_IP}/32
PersistentKeepalive = 25
EOF
systemctl enable wg-quick@wg0 >/dev/null 2>&1 || true
# reload config if already up, else bring up
if ip link show wg0 >/dev/null 2>&1; then
  wg syncconf wg0 <(wg-quick strip wg0)
  ip link set wg0 mtu "${WG_MTU}"
else
  systemctl restart wg-quick@wg0
fi
wg show wg0
REMOTE

  # --- 2.4 nftables DNAT relay (no SNAT -> source IPs preserved) ---
  log "2.4 installing nftables DNAT relay"
  rsh_script "RELAY_HOST=$RELAY_HOST" "RELAY_IFACE=$RELAY_IFACE" "TARGET_WG_IP=$TARGET_WG_IP" \
    "MGMT_SSH_PORT=$MGMT_SSH_PORT" "WG_PORT=$WG_PORT" <<'REMOTE'
set -euo pipefail
: "${RELAY_HOST:?}" "${RELAY_IFACE:?}" "${TARGET_WG_IP:?}" "${MGMT_SSH_PORT:?}" "${WG_PORT:?}"

install -d -m 0755 /etc/nftables.d
cat > /etc/nftables.d/ovhproxy.nft <<EOF
# Transparent DNAT relay to OVH over WireGuard (managed by relay-setup.sh).
# All TCP/UDP arriving on the public IP is forwarded to the OVH tunnel IP,
# except the local management SSH port and the WireGuard port. No SNAT, so
# the OVH host sees real client source addresses.
table inet ovhproxy {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        iifname "${RELAY_IFACE}" ip daddr ${RELAY_HOST} tcp dport != ${MGMT_SSH_PORT} dnat ip to ${TARGET_WG_IP}
        iifname "${RELAY_IFACE}" ip daddr ${RELAY_HOST} udp dport != ${WG_PORT} dnat ip to ${TARGET_WG_IP}
    }
    chain forward {
        # clamp TCP MSS to the tunnel path MTU so large packets survive
        type filter hook forward priority mangle; policy accept;
        tcp flags syn tcp option maxseg size set rt mtu
    }
}
EOF

# ensure /etc/nftables.conf loads our drop-in, then (re)load the ruleset
if ! grep -q '/etc/nftables.d/' /etc/nftables.conf; then
  printf '\ninclude "/etc/nftables.d/*.nft"\n' >> /etc/nftables.conf
fi
nft -f /etc/nftables.conf
systemctl enable nftables >/dev/null 2>&1 || true
systemctl restart nftables
echo "--- ovhproxy table ---"
nft list table inet ovhproxy
REMOTE

  log "Phase 2 complete."
  log "  - Selectel management ssh:  ssh -p ${MGMT_SSH_PORT} ${RELAY_SSH}"
  log "  - OVH via relay (all ports): e.g. ssh ${RELAY_SSH}  (lands on OVH)"
}

# ==========================================================================
main() {
  if [[ -n "${OVH_PUBKEY:-}" ]]; then
    phase2
  else
    phase1
    echo
    log "Phase 1 done. Deploy the OVH NixOS config with the Selectel pubkey above,"
    log "fetch the OVH pubkey, then run: OVH_PUBKEY=<key> $0"
  fi
}

main "$@"
