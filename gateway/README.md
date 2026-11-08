# iLink 路由器受限网关（v0.1）

网关是独立的 uhttpd + Lua 服务，使用系统已有组件，不安装 Python，不修改 LuCI 的 80/443 配置。

## 安全边界

只读接口（v0.1）：

- `GET /v1/status`、`GET /v1/clients`、`GET /v1/network`。

OpenClash 接口（v0.2，密钥留在路由器）：

- `GET /v1/openclash/status`、`GET /v1/openclash/groups`、`GET /v1/openclash/connections`
- `POST /v1/openclash/select`、`POST /v1/openclash/test-delay`、`POST /v1/openclash/close`
- `GET /v1/openclash/overview`（状态 + 代理组，一次往返）
- `GET /v1/openclash/configs`
- `POST /v1/openclash/mode`、`POST /v1/openclash/service`、`POST /v1/openclash/switch-config`

文件接口（v0.2，限定 `/mnt/data_sdb1`）：

- `POST /v1/files/list`、`mkdir`、`rename`、`remove`、`download`
- `POST /v1/files/upload`、`copy`、`move`、`preview`

固定规则：

- 控制器密钥只存于 `/etc/ilink/clash_secret`（root:ilink 0640），从不返回给客户端。
- 不提供 `/ubus`、LuCI、SSH、文件、shell、UCI 写入或通用 RPC 转发。
- 手机使用独立的 64 位十六进制 token；Android 将其保存在 Keystore 支持的安全存储中。
- 路由器内部使用无 shell 的 `ilink` 用户，仅可读取本版本需要的 RPC；无 UCI 权限。
- root 密码不被手机、网关或安装脚本使用。
- DDNSTO 仅映射 `127.0.0.1:8089`，外部使用其 HTTPS 域名。
- LAN 使用 `https://<LAN-IP>:8443`，Android 固定证书 SHA-256 指纹。
- 全部请求合计每秒钟最多 90 个，包含无效认证；失败认证写入系统日志，不记录 token。
- 所有响应禁止缓存，不返回内部 RPC 密码或 Wi-Fi 密钥。

DDNSTO 是公网入口，不是私有 VPN。token 泄露会让他人读取路由器型号、网络地址和客户端信息，因此必须像密码一样保管。撤销手机访问时，以 root 运行：

```sh
openssl rand -hex 32 > /etc/ilink/device_token
chown root:ilink /etc/ilink/device_token
chmod 0640 /etc/ilink/device_token
cat /etc/ilink/device_token
```

新 token 会在下一次请求时生效，无需重启。

## 安装（会修改路由器）

安装会创建低权限用户、网关配置和启动项，修改 `/etc/config/rpcd`，并重启 `rpcd`。现有 LuCI 的 RPC 会话可能失效，网页重新登录即可。请先备份并确认维护窗口。

```sh
# 将 gateway 目录上传到路由器后：
cd gateway
chmod +x install.sh test.sh ilink.init
sh install.sh
sh test.sh
```

安装脚本只显示一次手机 token 的读取结果；内部 RPC 密码不会打印。`/etc/ilink/backup/` 保留安装前的 rpcd 配置。

## DDNSTO 配置

在 DDNSTO 控制台为这台设备添加域名映射：

| 配置 | 值 |
|---|---|
| 外部访问 | `https://<你的前缀>.ddnsto.com` |
| 内网目标协议 | HTTP |
| 内网目标地址 | `127.0.0.1` |
| 内网目标端口 | `8089` |

**不要**将目标填成 `192.168.100.1:80`、`:443`、`:22` 或 `:8443`；8089 只接受 iLink 的受限业务接口。4M 套餐足够本版本的 JSON 状态查询。

## Android 配置

必填：

- DDNSTO 地址：`https://<你的前缀>.ddnsto.com`
- 设备凭据：安装输出的 64 位 token

可选 LAN 加速：

- LAN 地址：`https://192.168.100.1:8443`
- 证书 SHA-256：安装输出的指纹，冒号可有可无

填写 LAN 后会优先使用 LAN，连接失败才尝试 DDNSTO。认证失败不会自动换地址重试。

## 范围

- v0.1：系统状态、DHCP/host-hints 客户端、LAN/WAN/WAN6 接口和无线信息。
- v0.2：上述内容，加上 OpenClash 节点切换/测速/连接断开，以及 `/mnt/data_sdb1`
  下的目录浏览、建目录、重命名、删除空目录、下载（上限 32 MB）。
- v0.3：新增文件上传/复制/移动/预览，OpenClash 模式切换、服务启停与配置切换。
- v0.4：新增 `openclash/overview` 合并接口，并裁剪代理组响应字段。
- 不在范围：目录树复制、断点续传、Wi-Fi 修改、重启、备份恢复。

启停与配置切换由 rpcd 特权助手 `/usr/libexec/rpcd/ilink-action` 执行：rpcd 以 root 运行，
ubusd ACL 仅放行 `ilink` 的 `openclash`、`switch-config` 两个方法，参数为枚举与
`^[\w\-\.]+\.ya?ml$` 且必须真实存在的配置名，不拼接调用方命令。

文件接口对每次调用做规范化路径检查，拒绝 `..`、绝对路径、反斜杠与符号链接；
文件编解码只调用系统自带 `/usr/bin/openssl base64`（本机没有 `/usr/bin/base64`），
路径经 shell 转义，不接受调用方提供的命令文本。
