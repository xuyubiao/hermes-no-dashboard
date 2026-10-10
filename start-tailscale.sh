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

if [ -f "$STATE_FILE" ]; then
    echo "tailscale: state exists, trying state-first login" >&2
    if tailscale --socket="$SOCK" up --hostname="$HOSTNAME"; then
        # 2026-10-10: 不靠 state 文件存在判断登录态（tailscaled 首次启动会写只有
        # machine key 的 state，导致 10-05 的假阳性 bug），改靠 BackendState=Running
        for i in $(seq 1 15); do
            if tailscale --socket="$SOCK" status --json 2>/dev/null | grep -q '"BackendState": *"Running"'; then
                echo "tailscale: state login OK (BackendState=Running)" >&2
                LOGGED_IN=1
                break
            fi
            sleep 1
        done
    fi
    if [ -z "${LOGGED_IN:-}" ]; then
        echo "tailscale: state login failed, trying authkey fallback" >&2
        if [ -n "${TAILSCALE_AUTHKEY:-}" ]; then
            tailscale --socket="$SOCK" up --authkey="${TAILSCALE_AUTHKEY}" --hostname="$HOSTNAME" || \
                tailscale --socket="$SOCK" up --hostname="$HOSTNAME" || \
                echo "tailscale: up failed" >&2
        else
            # 2026-10-10 用户要求：无 key 时不报错，忽略继续（daemon 保持运行）
            echo "tailscale: no key for fallback, skipping (daemon stays running)" >&2
        fi
    fi
else
    if [ -n "${TAILSCALE_AUTHKEY:-}" ]; then
        echo "tailscale: no state file, using TAILSCALE_AUTHKEY" >&2
        tailscale --socket="$SOCK" up --authkey="${TAILSCALE_AUTHKEY}" --hostname="$HOSTNAME" || \
            tailscale --socket="$SOCK" up --hostname="$HOSTNAME" || \
            echo "tailscale: up failed" >&2
    fi
fi

echo "tailscale: up done, daemon pid $TPID" >&2
wait $TPID
