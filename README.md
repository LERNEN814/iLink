# iLink

面向 iStoreOS 的 Android 管理应用。v0.1 聚焦安全的只读远程管理，采用 DDNSTO + 路由器本地受限 API 网关，不公开暴露 LuCI、SSH 或通用 `/ubus`。

## 下载

[下载 iLink v0.1](https://github.com/LERNEN814/iLink/releases/tag/v0.1)。提供 arm64 APK、路由器网关源码包和 SHA-256 校验文件。APK 使用测试签名，不是应用商店正式签名。

## v0.2 功能

- 底部导航：**概览 / 代理 / 文件 / 工具**。
- 概览：系统信息，以及可展开的客户端与网络卡片。
- 代理：OpenClash 状态、代理组与节点切换、延迟测速、连接查看与断开。
- 文件：`/mnt/data_sdb1` 浏览、搜索、排序、新建文件夹、重命名、删除、下载。

## v0.1 功能

- 概览：型号、版本、运行时间、内存、负载、客户端与接口数量。
- 客户端：主机名、IP、MAC、厂商和连接类型。
- 网络：无线 SSID/信道/加密状态（不读取密钥）与 LAN/WAN/WAN6 信息。
- 工具：连接设置、主题切换、Liquid Glass 开关、本机凭据清除。
- DDNSTO 必选，LAN HTTPS 可选；LAN 不可用时自动切换 DDNSTO。
- Android 安全存储保存独立 token，不保存路由器 root 密码。
- 所有管理接口只读，不包含重启、Wi-Fi 修改或系统设置。

## 技术组成

- Android / Flutter 3.47+ / Dart 3.10+。
- 基于 [LuCI Mobile](https://github.com/cogwheel0/luci-mobile) 的数据模型与业务基础。
- 使用 [Prism UI](https://github.com/chen08209/prism_ui) 的 Liquid Glass、连续圆角、导航和转场，版本固定到 FlClash 对应提交。
- 路由器使用已有 Lua + uhttpd，无 Python 或额外运行时。
- GPL-3.0，上游历史和许可证保留，详见 [NOTICE](NOTICE)。

## 项目结构

```text
lib/ilink/       iLink UI、状态管理与受限网关客户端
lib/             LuCI Mobile 上游业务代码（保留供后续版本复用）
gateway/         路由器 Lua 网关、ACL、安装与测试脚本
test/            上游测试及 iLink 网络、UI 测试
```

## 构建

```sh
flutter pub get
dart analyze lib/main.dart lib/ilink
flutter test
flutter build apk --debug
```

调试 APK 位于 `build/app/outputs/flutter-apk/app-debug.apk`。发布包使用 `flutter build apk --release --split-per-abi` 构建；分发前需要配置你自己的签名。

这是 Android-only 项目。`tool/android_only_plugins/path_provider_foundation` 跳过了 Apple 专用原生构建钩子（该钩子在含空格的 Windows 用户目录下会失败）；Android 仍由 `path_provider_android` 提供实现。不要将此配置用于 iOS/macOS 构建。

## 部署与配置

部署必须由用户明确确认。安装会创建低权限账号、修改 rpcd 并启动网关，请先阅读 [gateway/README.md](gateway/README.md)，在维护窗口内执行。脚本不会自动运行。

配置概览：

1. 在路由器安装受限网关，保存安装输出的手机 token 与 LAN 证书指纹。
2. DDNSTO 域名映射到 `http://127.0.0.1:8089`，不是 LuCI 地址。
3. App 中填写 `https://<前缀>.ddnsto.com` 和 token。
4. 可选填写 `https://192.168.100.1:8443` 与证书 SHA-256 指纹。

## 验证

```sh
flutter test test/ilink_api_test.dart test/ilink_widget_test.dart
flutter test test/ilink_gateway_client_test.dart
sh -n gateway/install.sh gateway/test.sh gateway/ilink.init
lua gateway/test_gateway.lua  # 在 iStoreOS 上、仓库根目录执行
```

网关测试使用 mock RPC，不需要安装网关。安装后使用 `gateway/test.sh` 验证真实服务和权限。

## 后续版本

Wi-Fi 修改、重启、文件管理、软件中心和备份恢复不在 v0.1。写操作需要独立业务接口、严格参数校验和回滚机制，不能将现有只读网关改成通用 RPC 转发器。
