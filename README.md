# hermes-no-dashboard

Custom Hermes image based on `ghcr.io/insforge/insta-oss/templates/hermes:2.3.2`
with the dashboard disabled.

## What changed

`/entrypoint.sh` in the upstream image unconditionally ends with
`exec hermes dashboard ...`. This image patches it at build time to respect
the `HERMES_DASHBOARD` environment variable (same semantics as the s6
dashboard service):

- `HERMES_DASHBOARD=1/true/yes` → dashboard starts (upstream behavior)
- anything else / unset → entrypoint prints a note and `exec sleep infinity`

s6 stays PID 1 and keeps supervising `gateway-default` independently, so the
gateway is unaffected.

## Usage

Set `HERMES_DASHBOARD=false` (or leave unset) on the compute service and deploy
`ghcr.io/xuyubiao/hermes-no-dashboard:2.3.2`.
