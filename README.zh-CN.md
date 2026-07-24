# Caddy 远程白名单

[English](README.md)

仓库同时包含 Codex skill
[`centralize-caddy-whitelist`](skills/centralize-caddy-whitelist/SKILL.md)，可帮助用户扫描、去重和迁移已有的混乱白名单，同时保留不同访问策略组之间的边界。

将 `skills/centralize-caddy-whitelist` 放入 Codex skills 目录后，可以这样调用：

```text
使用 $centralize-caddy-whitelist 检查我现有的 Caddyfile，并在不改变访问权限的前提下将白名单迁移到这个项目。
```

将一份 Caddy 白名单片段放在 HTTPS 公网地址，所有服务器定时同步。每台服务器都会缓存最后一份有效配置，只有内容变化且完整 Caddy 配置校验通过后才会 reload。

## 远程片段

在 HTTPS 地址发布一个纯文本文件：

```caddyfile
@allowed remote_ip 192.0.2.10 198.51.100.0/24 203.0.113.25
```

同一个 `@allowed` matcher 请只定义一次，所有 IP 写在这一行。

## 修改 Caddyfile

将服务器原有的 IP 列表替换为一个本地 import：

```caddyfile
(restricted_clients) {
	import /etc/caddy/remote-whitelist.caddy
}
```

原有站点配置不需要改变：

```caddyfile
http://example.com:8317 {
	import restricted_clients

	handle @allowed {
		reverse_proxy 127.0.0.1:8817
	}

	handle {
		respond 403
	}
}
```

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/shuguangnet/caddy-remote-whitelist/main/install.sh \
  -o /tmp/caddy-remote-whitelist-install.sh

sudo sh /tmp/caddy-remote-whitelist-install.sh \
  --interval 5m
```

如果白名单数据仓库是私有仓库，一键安装时也可以直接指定令牌：

```bash
curl -fsSL https://raw.githubusercontent.com/shuguangnet/caddy-remote-whitelist/main/install.sh \
  -o /tmp/caddy-remote-whitelist-install.sh
sudo GITHUB_TOKEN="$GITHUB_TOKEN" sh /tmp/caddy-remote-whitelist-install.sh \
  --interval 5m
```

也可以克隆仓库后运行：

```bash
sudo ./install.sh \
  --interval 5m
```

安装器默认使用：

```text
https://raw.githubusercontent.com/shuguangnet/caddy-whitelist-data/main/allowed-clients.caddy
```

其他用户仍可通过 `--url` 指定自己的 HTTPS 白名单片段。

### 私有 GitHub 仓库

如果白名单数据仓库是私有仓库，可以在安装时提供一个有仓库内容读取权限的 GitHub token：

```bash
sudo sh /tmp/caddy-remote-whitelist-install.sh \
  --interval 5m \
  --github-token "$GITHUB_TOKEN"
```

安装器会把 token 保存到 `/etc/caddy-remote-whitelist.conf`，该文件权限为
`0600`。后续 systemd timer 同步时会自动带上这个 token 读取远程片段。

也可以通过环境变量传入：

```bash
sudo GITHUB_TOKEN="$GITHUB_TOKEN" ./install.sh \
  --interval 5m
```

推荐使用 fine-grained GitHub token，只授权白名单数据仓库，并只给
`Contents: Read-only` 权限。

### Docker / 1Panel

安装器会自动识别唯一运行中的 Caddy 容器，因此 1Panel 通常可以直接运行标准安装命令。也可以明确指定容器：

```bash
sh /tmp/caddy-remote-whitelist-install.sh \
  --docker-container 1Panel-caddy-5mTH \
  --interval 5m
```

Docker 模式默认使用容器内路径：

```text
Caddyfile: /etc/caddy/Caddyfile
白名单:    /etc/caddy/remote-whitelist.caddy
```

安装器会通过 `docker cp` 更新文件，并在容器内运行 `caddy validate` 和 `caddy reload`。请确保 Caddyfile 已包含：

```caddyfile
(restricted_clients) {
	import /etc/caddy/remote-whitelist.caddy
}
```

如果目标文件不在 Docker volume 或 bind mount 中，安装器会警告，因为容器重建后该文件可能丢失。

可自定义本地文件、Caddyfile 和服务名称：

```bash
sudo ./install.sh \
  --url https://config.example.com/allowed.caddy \
  --interval 1m \
  --target /etc/caddy/shared/allowed.caddy \
  --caddyfile /etc/caddy/Caddyfile \
  --service caddy
```

运行 `./install.sh --help` 可以查看全部参数。配置保存在权限为 `0600` 的 `/etc/caddy-remote-whitelist.conf`。

## 工作方式

- 只接受 HTTPS 地址。
- 下载结果不能为空，默认最大 1 MiB。
- 内容没有变化时不会 reload Caddy。
- 下载失败时继续使用最后一份有效文件。
- systemd 和 Docker 模式下，`caddy validate` 失败都会自动恢复旧文件。
- 默认由 systemd timer 每 5 分钟同步一次。

常用命令：

```bash
systemctl status caddy-remote-whitelist.timer
systemctl start caddy-remote-whitelist.service
journalctl -u caddy-remote-whitelist.service
```

## 卸载

```bash
sudo ./uninstall.sh
```

卸载程序会保留已经缓存的白名单，避免 Caddyfile 中现有的 import 立即失效。

## 安全说明

能够修改远程文件的人，也就能够修改所有服务器的访问白名单。请使用 HTTPS、保护好文件发布账户，并避免使用第三方可控制的地址。带查询参数的凭据会存储在本机 root-only 配置中，但仍可能出现在 Web 服务日志里；更推荐使用非敏感且难猜测的路径。
私有 GitHub 仓库建议使用只读 fine-grained token，并且只授权白名单数据仓库。命令行参数可能进入 shell history，交互安装时更推荐使用 `GITHUB_TOKEN` 环境变量。相比把凭据放在 URL 查询参数里，使用 Authorization header 更合适。

## License

MIT
