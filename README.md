# hermes-no-dashboard

Custom Hermes image based on `ghcr.io/insforge/insta-oss/templates/hermes:2.3.2`
with the dashboard disabled by default, plus an optional **picoclaw** agent.

## Agent selection

`AGENT_TYPE` (env/Secret) picks which agent runs. Only one runs at a time.

| `AGENT_TYPE` | Behavior |
|---|---|
| unset / `hermes` (default) | Hermes gateway. Dashboard follows `HERMES_DASHBOARD` (see below). |
| `picoclaw` | PicoClaw gateway (v0.3.1, pinned). Hermes s6 services are stopped. |

## Hermes mode

`/entrypoint.sh` respects `HERMES_DASHBOARD`:

- `HERMES_DASHBOARD=1/true/yes` → dashboard starts on 8080 (upstream behavior)
- unset/false (default) → dashboard off; a minimal 404 placeholder listens on
  8080 so the platform health check passes

## PicoClaw mode (`AGENT_TYPE=picoclaw`)

- Binaries: `picoclaw` + `picoclaw-launcher` v0.3.1 (pinned, linux amd64)
- `PICOCLAW_HOME` defaults to `/data/.picoclaw` (persistent volume); override via Secret
- `PICOCLAW_GATEWAY_HOST` defaults to `0.0.0.0`
- No auto `onboard` — write `$PICOCLAW_HOME/config.json` yourself

| `PICOCLAW_WEB_UI` | 8080 (public) | 18800 | gateway port |
|---|---|---|---|
| unset/false | gateway `/health` | — | 8080 |
| `true` | TCP forward → 18800 (WebUI) | `picoclaw-launcher -public` | 18789 (internal) |

With `PICOCLAW_WEB_UI=true`, open the service's public URL in a browser to
reach the launcher WebUI.

## Secrets

Set in InstaCloud: `AGENT_TYPE`, `PICOCLAW_WEB_UI`, `PICOCLAW_HOME`,
plus any `PICOCLAW_*` / `PC_*` picoclaw config. Changing a secret needs a
`restart` (env is resolved at deploy/restart time).
