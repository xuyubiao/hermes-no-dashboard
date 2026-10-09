# hermes-no-dashboard

Custom Hermes image based on `ghcr.io/insforge/insta-oss/templates/hermes:2.3.2`
with the dashboard disabled by default, plus an optional **picoclaw** agent,
Tailscale, sshd, and optional frpc.

## Secrets / 环境变量一览

在 InstaCloud 控制台 → Secrets 配置。改完后 `restart` 服务生效
（环境变量在 deploy/restart 时 bake 进容器）。

| 变量 | 示例值 | 说明 |
|---|---|---|
| `ADMIN_USERNAME` | `admin` | Hermes dashboard 的登录用户名（hermes 模式启用 dashboard 时用）。不可含冒号、换行或以 `-` 开头 |
| `ADMIN_PASSWORD` | `***` | Hermes dashboard 的登录密码 |
| `AGENT_TYPE` | `hermes` / `picoclaw` | **总开关**，决定跑哪个 agent。默认 `hermes`；设为 `picoclaw` 则只跑 picoclaw（互斥，hermes 的 s6 gateway 会被停掉） |
| `HERMES_DASHBOARD` | `false` | 仅 hermes 模式有效。`true`/`1`/`yes` → dashboard 监听 8080；其他值/不设 → dashboard 关闭，8080 起 404 占位服务（过平台健康检查） |
| `HERMES_HOME` | `/data/.hermes` | Hermes 的数据目录（config、gateway 状态等）。默认 `/data/.hermes`，持久化在 volume 上 |
| `PICOCLAW_HOME` | `/data/.picoclaw` | Picoclaw 的数据目录（`config.json`、workspace、session）。默认 `/data/.picoclaw`；**`config.json` 需手动进容器写**，镜像不做 `onboard` 预初始化 |
| `TAILSCALE_AUTHKEY` | `tskey-auth-***` | Tailscale 认证 key。**优先用已有 state**：`/data/tailscaled.state` 存在则直接 `tailscale up` 恢复会话（不耗 key）；无 state 才用 key；两者皆无则跳过不启动。hostname 默认 `instacloud-vm`（`TAILSCALE_HOSTNAME` 可改） |
| `FRPC_ARG` | `-c /data/frpc.toml` | frp 客户端启动参数。非空 → 后台启动 `frpc ${FRPC_ARG}`；为空则不启动 |
| `TELEGRAM_ALLOWED_USERS` | `12345678` | **Hermes** Telegram 渠道的用户白名单（用户 ID，多个用逗号分隔）。空则允许所有人 |
| `TELEGRAM_BOT_TOKEN` | `123456:ABC-***` | **Hermes** Telegram Bot 的 token（找 @BotFather 拿）。Hermes 通过它收发 Telegram 消息 |

## 端口速查

| 模式 | 8080（公网路由） | 18800 | 22 |
|---|---|---|---|
| hermes（默认） | 404 占位 | — | sshd（仅 Tailscale 可达） |
| hermes + `HERMES_DASHBOARD=true` | hermes dashboard | — | sshd |
| picoclaw | 404 占位 | `picoclaw-launcher -public`（仅 Tailscale 可达，如 `http://100.74.236.40:18800`）；launcher 自动管理 gateway 生命周期 | sshd |

## Tailscale + sshd

- `tailscaled` 以 `--tun=userspace-networking` 运行（容器无 TUN 权限），state 在 `/data/tailscaled.state`，重启不丢
- `sshd` 始终启动（s6 服务，root 运行）。`PermitRootLogin prohibit-password` + `PasswordAuthentication no`，只允许 key 登录；root 公钥 baked 在镜像 `/root/.ssh/authorized_keys`
- 22 端口无公网路由 → tailscale up 成功后，用 `ssh root@<tailscale-ip>`（如 `ssh root@100.74.236.40`）进容器

## frpc（frp 客户端）

- 镜像内置 `frpc` 二进制（`/usr/local/bin/frpc`）
- 设置 `FRPC_ARG` 后随容器启动（s6 服务），后台运行；为空则完全不启动
- 配置文件需自行挂载/写入，如 `/data/frpc.toml`，通过 `FRPC_ARG=-c /data/frpc.toml` 指定

## 版本 pin

| 组件 | 版本 |
|---|---|
| picoclaw / picoclaw-launcher | `v0.3.1`（GitHub Releases 预编译包） |
| tailscale / tailscaled | `1.102.4`（官方静态二进制） |
| frpc | 上游 master 分支预编译二进制（ADBlock-Rules 仓库） |
