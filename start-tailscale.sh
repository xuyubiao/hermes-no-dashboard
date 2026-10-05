#!/bin/sh
# Start tailscaled (userspace networking) and bring Tailscale up.
# Priority: existing state first, then authkey, else skip.
# State persists at /data/tailscaled.state.
set -e

STATE_FILE="/data/tailscaled.state"
SOCK_DIR="/var/run/tailscale"
SOCK="$SOCK_DIR/tailscaled.sock"
HOSTNAME="${TAILSCALE_HOSTNAME:-instacloud-vm}"

if [ ! -f "$STATE_FILE" ] && [ -z "${TAILSCALE_AUTHKEY:-}" ]; then
    echo "tailscale: no state and no TAILSCALE_AUTHKEY, skipping" >&2
    exit 0
fi

mkdir -p "$SOCK_DIR" /data
echo "tailscale: starting tailscaled (userspace-networking)" >&2
tailscaled --tun=userspace-networking --state="$STATE_FILE" --socket="$SOCK" &
TPID=$!

# Wait for the socket (max ~30s)
for i in $(seq 1 30); do
    if [ -S "$SOCK" ]; then break; fi
    sleep 1
done
if [ ! -S "$SOCK" ]; then
    echo "tailscale: daemon socket not ready, giving up" >&2
    exit 1
fi

if [ -n "${TAILSCALE_AUTHKEY:-}" ]; then
    echo "tailscale: using TAILSCALE_AUTHKEY" >&2
    tailscale --socket="$SOCK" up --authkey="${TAILSCALE_AUTHKEY}" --hostname="$HOSTNAME" || \
        tailscale --socket="$SOCK" up --hostname="$HOSTNAME" || \
        echo "tailscale: up failed" >&2
else
    echo "tailscale: no key, restoring from state" >&2
    tailscale --socket="$SOCK" up --hostname="$HOSTNAME" || \
        echo "tailscale: up failed (need authkey)" >&2
fi

echo "tailscale: up done, daemon pid $TPID" >&2
wait $TPID
