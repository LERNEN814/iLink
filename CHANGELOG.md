# Changelog

## v0.2 — 2026-11-09

### 新增

- 底部导航调整为 **概览 / 代理 / 文件 / 工具**；原「客户端」「网络」并入概览卡片。
- **代理页**：OpenClash 运行状态、核心版本、配置名、模式、混合端口、连接数与上下行；
  代理组标签、节点卡片、延迟测速、节点切换；活跃连接查看与断开；累计流量。
- **文件页**：浏览 `/mnt/data_sdb1`、面包屑返回、搜索、名称排序、容量显示、
  新建文件夹、重命名、删除（仅空文件夹）、下载到手机应用文档目录。
- 网关新增固定接口：`openclash/{status,groups,connections,select,test-delay,close}`、
  `files/{list,mkdir,rename,remove,download}`。
- 网关读取 OpenClash 控制器密钥仅存于路由器（`/etc/ilink/clash_secret`），不下发客户端。

### 安全

- 文件操作只允许 `/mnt/data_sdb1` 规范化路径，拒绝 `..`、绝对路径、反斜杠与符号链接。
- OpenClash 参数经白名单校验，拒绝路径穿越与换行注入；控制器 secret 不返回给客户端。
- 限流覆盖无效认证请求；写入方法需 POST 且仅限固定路由。

### 验证

- Flutter 测试 504 项通过（含 OpenClash/文件页面与 HTTPS 契约测试）。
- 网关单元测试：认证/路由/限流、分块 HTTP 与参数过滤、文件路径隔离。
- 真机 iStoreOS 24.10.8：`status` 248B、`groups` 61KB、`connections` 17KB、
  文件列表、节点测速 46ms、路径逃逸被拒、密钥零泄露。

### 已知限制

- 文件下载上限 32 MB，经 Base64 传输；大文件与断点续传留待后续版本。
- 不做上传、预览、复制移动；配置切换与启停不在本版。
- OpenClash 启停/模式切换、网络配置回滚与通知栏传输任务列入 v0.6 目标。

## v0.1 — 2026-11-08

首个 iLink Android 版本。

### 功能

- 概览、客户端、网络、工具四个页面。
- 基于 Prism UI 的 Liquid Glass 浮动导航、连续圆角卡片与页面转场。
- DDNSTO 远程访问，支持可选 LAN HTTPS 加速及失败切换。
- Android 安全存储保存独立设备 token，不保存 root 密码。
- LAN 自签名证书 SHA-256 固定，拒绝 HTTP 与重定向。
- 明暗主题、玻璃效果开关和本机配置清除。
- 独立应用图标、名称与 Android 包名 `com.istoreos.ilink`。

### 路由器网关

- 固定只读接口：`GET /v1/status`、`GET /v1/clients`、`GET /v1/network`。
- 独立低权限 `ilink` 用户与最小 RPC ACL，无 UCI 或写权限。
- DDNSTO 仅映射 loopback 网关，不暴露 LuCI、SSH 或通用 `/ubus`。
- 无效认证与有效请求均受限流保护；认证失败记录日志但不记录 token。
- 使用 iStoreOS 已有的 Lua 与 uhttpd，无 Python 或额外运行时。

### 验证

- 501 项 Flutter 测试通过。
- 网关认证、固定路径、只读 RPC 与限流测试通过。
- 在 FriendlyElec NanoPi R3S / iStoreOS 24.10.8 上验证三个真实接口。
- Android 实机安装与使用、LAN HTTPS 和 DDNSTO 外网连接均已确认。

### 范围与安装说明

- v0.1 仅提供只读管理，不包含 Wi-Fi 修改、重启、文件或备份恢复。
- Release APK 面向 arm64 Android 7.0 及以上设备，使用测试签名，不是应用商店正式签名。
