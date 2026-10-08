FROM ghcr.io/insforge/insta-oss/templates/hermes:2.3.2

# Pinned picoclaw version
ARG PICOCLAW_VERSION=v0.3.1

# Install picoclaw + picoclaw-launcher (prebuilt, linux amd64)
RUN curl -fsSL -o /tmp/picoclaw.tar.gz \
        "https://github.com/sipeed/picoclaw/releases/download/${PICOCLAW_VERSION}/picoclaw_Linux_x86_64.tar.gz" && \
    tar -xzf /tmp/picoclaw.tar.gz -C /usr/local/bin/ picoclaw picoclaw-launcher && \
    chmod +x /usr/local/bin/picoclaw /usr/local/bin/picoclaw-launcher && \
    rm /tmp/picoclaw.tar.gz && \
    test -x /usr/local/bin/picoclaw && test -x /usr/local/bin/picoclaw-launcher && \
    echo "picoclaw binaries installed"

# Install tailscale (pinned, static binaries, linux amd64)
ARG TAILSCALE_VERSION=1.102.4
RUN curl -fsSL -o /tmp/tailscale.tgz \
        "https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_amd64.tgz" && \
    tar -xzf /tmp/tailscale.tgz -C /tmp && \
    cp /tmp/tailscale_${TAILSCALE_VERSION}_amd64/tailscaled /tmp/tailscale_${TAILSCALE_VERSION}_amd64/tailscale /usr/local/bin/ && \
    chmod +x /usr/local/bin/tailscaled /usr/local/bin/tailscale && \
    rm -rf /tmp/tailscale.tgz /tmp/tailscale_${TAILSCALE_VERSION}_amd64 && \
    test -x /usr/local/bin/tailscaled && test -x /usr/local/bin/tailscale && \
    echo "tailscale binaries installed"

# Install frpc (prebuilt binary)
RUN curl -fsSL -o /usr/local/bin/frpc \
        "https://raw.githubusercontent.com/xuyubiao/ADBlock-Rules/master/frpc" && \
    chmod +x /usr/local/bin/frpc && \
    test -x /usr/local/bin/frpc && \
    echo "frpc binary installed"

# Install openssh-server, configure root key-only auth
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /run/sshd /root/.ssh && chmod 700 /root/.ssh && \
    ssh-keygen -A && \
    printf '%s\n' \
        "PermitRootLogin prohibit-password" \
        "PasswordAuthentication no" \
        "ChallengeResponseAuthentication no" \
        "UsePAM no" \
        >> /etc/ssh/sshd_config && \
    echo "openssh-server installed"

# Root authorized key (user-provided id_rsa.pub)
COPY id_rsa.pub /root/.ssh/authorized_keys
RUN chmod 600 /root/.ssh/authorized_keys

# Tailscale startup helper
COPY start-tailscale.sh /usr/local/bin/start-tailscale.sh
RUN chmod +x /usr/local/bin/start-tailscale.sh

# frpc startup helper
COPY start-frpc.sh /usr/local/bin/start-frpc.sh
RUN chmod +x /usr/local/bin/start-frpc.sh

# s6 services: sshd (root) and tailscale (root)
# sshd: longrun, no daemonize (-D), log to stderr (-e)
RUN mkdir -p /etc/s6-overlay/s6-rc.d/sshd && \
    printf 'longrun\n' > /etc/s6-overlay/s6-rc.d/sshd/type && \
    printf '#!/command/with-contenv sh\nmkdir -p /run/sshd\nexec /usr/sbin/sshd -D -e\n' > /etc/s6-overlay/s6-rc.d/sshd/run && \
    chmod +x /etc/s6-overlay/s6-rc.d/sshd/run && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/sshd && \
    echo "sshd s6 service added"

# tailscale: longrun wrapper (daemon + up)
RUN mkdir -p /etc/s6-overlay/s6-rc.d/tailscale && \
    printf 'longrun\n' > /etc/s6-overlay/s6-rc.d/tailscale/type && \
    printf '#!/command/with-contenv sh\n# Skip if no state and no key (finish 125 = stay down)\nif [ ! -f /data/tailscaled.state ] && [ -z "${TAILSCALE_AUTHKEY:-}" ]; then exit 0; fi\nexec /usr/local/bin/start-tailscale.sh\n' > /etc/s6-overlay/s6-rc.d/tailscale/run && \
    printf '#!/command/with-contenv sh\nexit 125\n' > /etc/s6-overlay/s6-rc.d/tailscale/finish && \
    chmod +x /etc/s6-overlay/s6-rc.d/tailscale/run /etc/s6-overlay/s6-rc.d/tailscale/finish && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/tailscale && \
    echo "tailscale s6 service added"

# frpc: longrun wrapper (nohup background start when FRPC_ARG set)
RUN mkdir -p /etc/s6-overlay/s6-rc.d/frpc && \
    printf 'longrun\n' > /etc/s6-overlay/s6-rc.d/frpc/type && \
    printf '#!/command/with-contenv sh\n# Skip when FRPC_ARG empty\nif [ -z "${FRPC_ARG:-}" ]; then exit 0; fi\nexec /usr/local/bin/start-frpc.sh\n' > /etc/s6-overlay/s6-rc.d/frpc/run && \
    printf '#!/command/with-contenv sh\nexit 125\n' > /etc/s6-overlay/s6-rc.d/frpc/finish && \
    chmod +x /etc/s6-overlay/s6-rc.d/frpc/run /etc/s6-overlay/s6-rc.d/frpc/finish && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/frpc && \
    echo "frpc s6 service added"

# Dashboard 404 placeholder (keeps the routed port listening for health check)
COPY dashboard-placeholder.py /usr/local/bin/dashboard-placeholder.py
RUN chmod +x /usr/local/bin/dashboard-placeholder.py && \
    python3 -m py_compile /usr/local/bin/dashboard-placeholder.py

# s6 dashboard: stay down in picoclaw mode (DISABLED for debugging)
# RUN python3 - <<'PYEOF'
# p = "/etc/s6-overlay/s6-rc.d/dashboard/run"
# with open(p) as f:
#     content = f.read()
# guard = '# Patched: stay down when AGENT_TYPE=picoclaw\ncase "${AGENT_TYPE:-hermes}" in\n    picoclaw) exit 0 ;;\nesac'
# if "AGENT_TYPE" not in content:
#     lines = content.split("\n")
#     lines.insert(1, guard)
#     with open(p, "w") as f:
#         f.write("\n".join(lines))
#     print("dashboard run patched")
# PYEOF

# Patch /entrypoint.sh: AGENT_TYPE switch
RUN python3 - <<'PYEOF'
with open("/entrypoint.sh") as f:
    lines = f.readlines()

for i, l in enumerate(lines):
    if l.strip().startswith("exec hermes dashboard"):
        patch = """# Patched: AGENT_TYPE switch (hermes default, picoclaw optional)
# Note: sshd and tailscale run as s6 services (see s6-rc.d/sshd, s6-rc.d/tailscale)
case "${AGENT_TYPE:-hermes}" in
    picoclaw)
        echo "entrypoint: AGENT_TYPE=picoclaw" >&2
        export PICOCLAW_HOME="${PICOCLAW_HOME:-/data/.picoclaw}"
        mkdir -p "$PICOCLAW_HOME" 2>/dev/null || echo "entrypoint: warning: cannot mkdir $PICOCLAW_HOME (create it manually via exec)" >&2
        if [ -d /run/service/gateway-default ]; then
            s6-svc -d /run/service/gateway-default 2>/dev/null || true
            echo "entrypoint: stopped hermes gateway-default" >&2
        fi
        export PICOCLAW_GATEWAY_HOST="${PICOCLAW_GATEWAY_HOST:-0.0.0.0}"
        if [ "${PICOCLAW_WEB_UI:-}" = "true" ]; then
            echo "entrypoint: starting picoclaw-launcher on 0.0.0.0:18800 (Tailscale only)" >&2
            picoclaw-launcher -public &
            export PICOCLAW_GATEWAY_PORT="${PICOCLAW_GATEWAY_PORT:-18789}"
            # 8080: 404 placeholder for health check (gateway stays internal)
            PLACEHOLDER_BODY="not found" python3 /usr/local/bin/dashboard-placeholder.py &
            echo "entrypoint: placeholder on 8080" >&2
        else
            export PICOCLAW_GATEWAY_PORT="${PICOCLAW_GATEWAY_PORT:-8080}"
        fi
        echo "entrypoint: starting picoclaw gateway on ${PICOCLAW_GATEWAY_HOST}:${PICOCLAW_GATEWAY_PORT}" >&2
        # Run gateway in background; keep container alive if it exits (e.g. no config yet)
        picoclaw gateway &
        _gw_pid=$!
        wait $_gw_pid || true
        _gw_code=$?
        echo "entrypoint: picoclaw gateway exited (code $_gw_code), keeping container alive" >&2
        if [ "${PICOCLAW_WEB_UI:-}" = "true" ]; then
            # placeholder already on 8080 in background
            exec sleep infinity
        else
            # gateway was on 8080 and exited; placeholder takes over
            export PLACEHOLDER_BODY="not found"
            exec python3 /usr/local/bin/dashboard-placeholder.py
        fi
        ;;
    *)
        case "${HERMES_DASHBOARD:-}" in
            1|true|TRUE|True|yes|YES|Yes) ;;
            *)
                echo "entrypoint: dashboard disabled, starting placeholder on port ${HERMES_DASHBOARD_PORT:-8080}" >&2
                export PLACEHOLDER_BODY="dashboard disabled"
                exec python3 /usr/local/bin/dashboard-placeholder.py
                ;;
        esac
        ;;
esac
"""
        lines.insert(i, patch)
        break
else:
    raise SystemExit("dashboard exec line not found in /entrypoint.sh")

with open("/entrypoint.sh", "w") as f:
    f.writelines(lines)
print("entrypoint patched")
PYEOF

RUN bash -n /entrypoint.sh && \
    grep -q "AGENT_TYPE" /entrypoint.sh && \
    test -x /etc/s6-overlay/s6-rc.d/sshd/run && \
    test -x /etc/s6-overlay/s6-rc.d/tailscale/run && \
    test -f /etc/s6-overlay/s6-rc.d/user/contents.d/sshd && \
    test -f /etc/s6-overlay/s6-rc.d/user/contents.d/tailscale && \
    test -x /etc/s6-overlay/s6-rc.d/frpc/run && \
    test -f /etc/s6-overlay/s6-rc.d/user/contents.d/frpc && \
    which picoclaw picoclaw-launcher tailscaled tailscale frpc
