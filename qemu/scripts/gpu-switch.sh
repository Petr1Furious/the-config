#!/run/current-system/sw/bin/bash
set -euo pipefail

DOMAIN="${1:-}"
HOOK="${2:-}"
PHASE="${3:-}"

SW="/run/current-system/sw/bin"

SYSTEMCTL="$SW/systemctl"
MODPROBE="$SW/modprobe"
FUSER="$SW/fuser"
SLEEP="$SW/sleep"
TIMEOUT="$SW/timeout"
VIRSH="$SW/virsh"
DATE="$SW/date"

LOGFILE="/var/log/libvirt-gpu-switch.log"
log() { printf '%s %s\n' "$("$DATE" -Is)" "$1" >>"$LOGFILE" 2>/dev/null || true; }

if [[ "$DOMAIN" != "win11" ]]; then
  exit 0
fi

NODEDEVS=(
  pci_0000_01_00_0
  pci_0000_01_00_1
)

stop_host_nvidia_users() {
  if "$FUSER" -a /dev/nvidia* >/dev/null 2>&1; then
    "$FUSER" -TERM -a /dev/nvidia* >/dev/null 2>&1 || true
    "$SLEEP" 1
    "$FUSER" -KILL -a /dev/nvidia* >/dev/null 2>&1 || true
    "$SLEEP" 1
  fi
}

start_host_nvidia() {
  "$MODPROBE" nvidia 2>/dev/null || true
  "$MODPROBE" nvidia_uvm 2>/dev/null || true
}

unload_nvidia_modules() {
  "$MODPROBE" -r nvidia_uvm nvidia
}

detach_to_vfio() {
  "$MODPROBE" vfio-pci 2>/dev/null || true
  for dev in "${NODEDEVS[@]}"; do
    "$VIRSH" --connect qemu:///system nodedev-detach "$dev"
  done
}

reattach_to_host() {
  for dev in "${NODEDEVS[@]}"; do
    "$VIRSH" --connect qemu:///system nodedev-reattach "$dev"
  done
}

case "$HOOK/$PHASE" in
  prepare/begin)
    log "prepare/begin: detaching GPU for VM"
    stop_host_nvidia_users
    for _ in 1 2 3 4 5; do
      if unload_nvidia_modules 2>/dev/null; then
        break
      fi
      "$SLEEP" 1
    done
    unload_nvidia_modules
    detach_to_vfio
    ;;

  release/end)
    log "release/end: reattaching GPU to host"
    reattach_to_host
    start_host_nvidia
    ;;

  *)
    ;;
esac
