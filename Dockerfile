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

# TCP forwarder: 8080 -> 127.0.0.1:18800 (for WebUI public access)
COPY tcp-forward.py /usr/local/bin/tcp-forward.py
RUN chmod +x /usr/local/bin/tcp-forward.py

# Dashboard 404 placeholder (for hermes mode with dashboard disabled)
COPY dashboard-placeholder.py /usr/local/bin/dashboard-placeholder.py
RUN chmod +x /usr/local/bin/dashboard-placeholder.py

# s6 dashboard: also respect AGENT_TYPE (stay down in picoclaw mode)
RUN python3 - <<'PYEOF'
p = "/etc/s6-overlay/s6-rc.d/dashboard/run"
with open(p) as f:
    content = f.read()
guard = '# Patched: stay down when AGENT_TYPE=picoclaw\ncase "${AGENT_TYPE:-hermes}" in\n    picoclaw) exit 0 ;;\nesac'
if "AGENT_TYPE" not in content:
    lines = content.split("\n")
    lines.insert(1, guard)
    with open(p, "w") as f:
        f.write("\n".join(lines))
    print("dashboard run patched")
else:
    print("dashboard run already patched")
PYEOF

# Patch /entrypoint.sh:
#   AGENT_TYPE=picoclaw -> run picoclaw (gateway, +launcher if PICOCLAW_WEB_UI=true)
#   default (hermes)    -> HERMES_DASHBOARD gate (dashboard or 404 placeholder on 8080)
RUN python3 - <<'PYEOF'
with open("/entrypoint.sh") as f:
    lines = f.readlines()

for i, l in enumerate(lines):
    if l.strip().startswith("exec hermes dashboard"):
        patch = """# Patched: AGENT_TYPE switch (hermes default, picoclaw optional)
case "${AGENT_TYPE:-hermes}" in
    picoclaw)
        echo "entrypoint: AGENT_TYPE=picoclaw" >&2
        export PICOCLAW_HOME="${PICOCLAW_HOME:-/data/.picoclaw}"
        mkdir -p "$PICOCLAW_HOME"
        if [ -d /run/service/gateway-default ]; then
            s6-svc -d /run/service/gateway-default 2>/dev/null || true
            echo "entrypoint: stopped hermes gateway-default" >&2
        fi
        export PICOCLAW_GATEWAY_HOST="${PICOCLAW_GATEWAY_HOST:-0.0.0.0}"
        if [ "${PICOCLAW_WEB_UI:-}" = "true" ]; then
            echo "entrypoint: starting picoclaw-launcher on 0.0.0.0:18800" >&2
            picoclaw-launcher -public &
            echo "entrypoint: WebUI publicly accessible via service URL (forwarded to :18800)" >&2
            python3 /usr/local/bin/tcp-forward.py &
            export PICOCLAW_GATEWAY_PORT="${PICOCLAW_GATEWAY_PORT:-18789}"
        else
            export PICOCLAW_GATEWAY_PORT="${PICOCLAW_GATEWAY_PORT:-8080}"
        fi
        echo "entrypoint: starting picoclaw gateway on ${PICOCLAW_GATEWAY_HOST}:${PICOCLAW_GATEWAY_PORT}" >&2
        exec picoclaw gateway
        ;;
    *)
        case "${HERMES_DASHBOARD:-}" in
            1|true|TRUE|True|yes|YES|Yes) ;;
            *)
                echo "entrypoint: dashboard disabled, starting placeholder on port ${HERMES_DASHBOARD_PORT:-8080}" >&2
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

# Sanity checks
RUN bash -n /entrypoint.sh && \
    python3 -m py_compile /usr/local/bin/tcp-forward.py /usr/local/bin/dashboard-placeholder.py && \
    grep -q "AGENT_TYPE" /entrypoint.sh && \
    grep -q "AGENT_TYPE" /etc/s6-overlay/s6-rc.d/dashboard/run && \
    which picoclaw picoclaw-launcher
