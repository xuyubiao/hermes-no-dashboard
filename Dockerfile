FROM ghcr.io/insforge/insta-oss/templates/hermes:2.3.2

# Disable dashboard: patch /entrypoint.sh to respect HERMES_DASHBOARD.
# Upstream entrypoint unconditionally execs "hermes dashboard"; this inserts
# a gate:
#   HERMES_DASHBOARD=1/true/yes -> dashboard starts (upstream behavior)
#   unset/false (default)       -> dashboard stays off; a minimal placeholder
#                                HTTP server listens on the dashboard port so
#                                the platform health check still passes.
RUN python3 - <<'PYEOF'
with open("/entrypoint.sh") as f:
    lines = f.readlines()
for i, l in enumerate(lines):
    if l.strip().startswith("exec hermes dashboard"):
        patch = """# Patched: respect HERMES_DASHBOARD (default: disabled)
case "${HERMES_DASHBOARD:-}" in
    1|true|TRUE|True|yes|YES|Yes) ;;
    *)
        echo "entrypoint: dashboard disabled, starting placeholder on port ${HERMES_DASHBOARD_PORT:-8080}" >&2
        exec python3 -c '
import http.server, os
_PORT = int(os.environ.get("HERMES_DASHBOARD_PORT", "8080"))
class _H(http.server.BaseHTTPRequestHandler):
    def _deny(self):
        self.send_response(404); self.end_headers()
        self.wfile.write(b"dashboard disabled")
    do_GET = _deny; do_POST = _deny; do_PUT = _deny; do_DELETE = _deny
    def log_message(self, *a): pass
http.server.HTTPServer(("0.0.0.0", _PORT), _H).serve_forever()
'
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

# Sanity check: syntax valid and patch present
RUN bash -n /entrypoint.sh && grep -q "Patched: respect HERMES_DASHBOARD" /entrypoint.sh
