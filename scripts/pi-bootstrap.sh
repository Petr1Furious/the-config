#!/usr/bin/env bash
#
# pi-bootstrap.sh — bring a fresh Raspberry Pi OS install up to the point where
# home-manager (homeConfigurations."$USER@$(hostname)") manages everything else.
#
# Runs on the Pi as the regular user, from a clone of this repo. Idempotent —
# safe to re-run.
#
# Usage:
#   sudo apt install -y git
#   git clone https://github.com/Petr1Furious/the-config ~/cfg
#   ~/cfg/scripts/pi-bootstrap.sh
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BSEC_ZIP="${BSEC_ZIP:-$HOME/bsec_v3-3-0-1.zip}"
NIX_BIN="/nix/var/nix/profiles/default/bin"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

log "passwordless sudo"
sudoers="/etc/sudoers.d/010-$USER-nopasswd"
tmp="$(mktemp)"
echo "$USER ALL=(ALL) NOPASSWD: ALL" >"$tmp"
if ! sudo cmp -s "$tmp" "$sudoers"; then
  sudo visudo -cqf "$tmp"
  sudo install -m 0440 -o root -g root "$tmp" "$sudoers"
fi
rm -f "$tmp"

log "I2C"
if [ "$(sudo raspi-config nonint get_i2c)" != 0 ]; then
  sudo raspi-config nonint do_i2c 0
fi
if ! id -nG "$USER" | grep -qw i2c; then
  sudo usermod -aG i2c "$USER"
  log "added $USER to i2c; log in again for it to apply"
fi

log "activity LED off"
config=/boot/firmware/config.txt
# No act_led_activelow: the Pi 5's LED polarity differs from older boards,
# and the trigger alone keeps it off.
if ! grep -qx "dtparam=act_led_trigger=none" "$config"; then
  printf '\n[all]\ndtparam=act_led_trigger=none\n' | sudo tee -a "$config" >/dev/null
fi

log "cloud-init off"
# Imager's first-boot setup is done; otherwise it re-reads its seed every boot.
if [ -d /etc/cloud ]; then
  sudo touch /etc/cloud/cloud-init.disabled
fi

log "Nix"
if [ ! -x "$NIX_BIN/nix" ]; then
  sh <(curl -fsSL https://nixos.org/nix/install) --daemon --yes
fi
if ! grep -q '^experimental-features.*flakes' /etc/nix/nix.conf; then
  echo 'experimental-features = nix-command flakes' | sudo tee -a /etc/nix/nix.conf >/dev/null
  sudo systemctl restart nix-daemon
fi
export PATH="$NIX_BIN:$PATH"

log "Tailscale"
if ! command -v tailscale >/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
if ! tailscale status >/dev/null 2>&1; then
  sudo tailscale up --advertise-exit-node
fi

log "systemd user services without a login session"
sudo loginctl enable-linger "$USER"

log "BSEC"
if [ -f "$BSEC_ZIP" ]; then
  nix-store --add-fixed sha256 "$BSEC_ZIP" >/dev/null
else
  log "no $BSEC_ZIP; the exporter won't build until it's added (see pkgs/bme688-exporter)"
fi

log "home-manager"
nix shell --inputs-from "$REPO" home-manager -c home-manager switch --flake "$REPO"

log "login shell"
zsh="$HOME/.nix-profile/bin/zsh"
grep -qxF "$zsh" /etc/shells || echo "$zsh" | sudo tee -a /etc/shells >/dev/null
if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$zsh" ]; then
  sudo chsh -s "$zsh" "$USER"
fi

log "done"
