FROM ghcr.io/insforge/insta-oss/templates/hermes:2.3.2

# Disable dashboard: patch /entrypoint.sh to respect HERMES_DASHBOARD.
# Upstream entrypoint unconditionally execs "hermes dashboard"; this inserts
# a gate so the dashboard only starts when HERMES_DASHBOARD is truthy.
# With HERMES_DASHBOARD=false/empty, the container idles (s6 keeps supervising
# the gateway service independently).
RUN python3 - <<'PYEOF'
with open("/entrypoint.sh") as f:
    lines = f.readlines()
for i, l in enumerate(lines):
    if l.strip().startswith("exec hermes dashboard"):
        patch = """# Patched: respect HERMES_DASHBOARD (operator disabled dashboard)
case "${HERMES_DASHBOARD:-}" in
    1|true|TRUE|True|yes|YES|Yes) ;;
    *) echo "entrypoint: dashboard disabled, idling" >&2; exec sleep infinity ;;
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
