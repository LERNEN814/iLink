# Changelog

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
