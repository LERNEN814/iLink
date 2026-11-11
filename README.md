# iLink

面向 iStoreOS 的 Android 管理应用。通过 **DDNSTO + 路由器本地受限网关**工作，
不暴露 LuCI、SSH 或通用 `/ubus`，App 里没有一条 SSH 命令。

- 界面沿用 [Prism UI](https://github.com/chen08209/prism_ui)（FlClash 同款）：
  流光玻璃、连续圆角、浮动导航、滑动转场。
- 数据模型与部分业务逻辑来自 [LuCI Mobile](https://github.com/cogwheel0/luci-mobile)。
- 仅 Android。GPL-3.0，上游历史与许可证保留，见 [NOTICE](NOTICE)。

## 下载

| 文件 | 说明 |
|---|---|
| `iLink-vX.Y.Z-arm64.apk` | Android arm64 APK |
| `iLink-gateway-vX.Y.Z.zip` | 路由器网关（Lua，无额外运行时） |
| `SHA256SUMS-vX.Y.Z` | 校验文件 |

最新版本见 [Releases](https://github.com/LERNEN814/iLink/releases/latest)。
APK 目前使用 **debug keystore 测试签名**，不是应用商店正式签名。
v1.0.0 是当前的功能终版；再发布请自行用正式 keystore 重新签名。

## 功能

### 概览

- **出口 IP 卡片**：当前代理出口地址、类型（原生家宽 / 移动网络 / 商业宽带 / 机房 IP）、
  信誉等级与评分、国家城市、归属组织与 ASN、风险标记（代理 / VPN / Tor / 滥用）。
  机制移植自 FlClash 的 `ip_quality`：先经代理取真实出口，再查公开 IP 库。
- **实时流量看板**：每秒采样 WAN 计数器，下行/上行同坐标系双色平滑曲线，
  纵向按最近 60 个采样峰值自适应。
- 系统信息、内存使用、系统负载。
- **可折叠卡片**：服务状态（6 个）、在线设备、网络接口。
- 顶栏两种状态：静止时内容在状态栏下方；上滑后顶栏淡出、内容延伸至状态栏下。

设备列表只保留 LAN 子网内的真实邻居：已排除 docker 网桥（`02:42:*`）、隧道与
CGNAT 对端、路由自身 IP 和重复 MAC。

### 代理（OpenClash）

- 状态、模式（规则/全局/直连）、启动/停止/重启服务；
- 代理组分页与节点切换；
- **一键测速**：6 路并发的单节点探测池，测完一个亮一个；
- 连接列表与单条断开；
- 配置文件列表：**真实流量条**（订阅流量与到期时间）、切换配置；
- 当前配置以 `uci openclash.config.config_path` 为准——LuCI、SSH 或任何终端里
  切换的配置，刷新即显示。

服务停止时页面显示独立卡片，可**直接从 App 启动**（此前是死锁）。

### 文件

- 两个来源：**路由器存储**（`/mnt/data_sdb1`）与 **AList**。
- 浏览、搜索、排序、新建文件夹、重命名、复制、移动、删除。
- 点击文件弹出**预览 / 下载**确认：
  - 预览：视频/音频用内置 **mpv**（libmpv）全屏播放，支持字幕、倍速、手势；
    文本与图片用网关预览；其他类型仅下载。
  - 下载：流式写入手机 **`Download/idownload`**（Android 10+ 经 MediaStore，
    无需存储权限；Android 9- 首次需授权），路由器文件**无大小上限**，
    进度只显示在对应文件那一行。
- 播放地址使用**短时票据**（15 分钟、路径锁定、过期自动清理），
  mpv 进程不持有长期设备令牌。
- LAN 播放经独立流媒体进程（`8444`，支持 Range/拖动）；远程播放走网关 CGI。

### 工具

- **下载器**：磁链/种子 → qBittorrent（`/mnt/data_sdb1/download`）；
  视频/m3u8 链接 → yt-dlp（`/mnt/data_sdb1/video`）。任务列表与移除。
- **网络体检**：快速连通性、NAT 类型、IPv6。
- **终端**：二次确认后以 root 在路由器上执行命令（30 秒超时），输出可复制。
- **固件 / 应用两列**：
  - 固件：App 下发指令检查系统组件版本；刷写跳系统浏览器到 LuCI；
  - 应用：一键升级可升级包，升级前记录运行中的服务并在完成后重启。
    iStoreOS 用 `hold` 锁定的包（`base-files`、`luci-*`、`openssl` 等）
    会被过滤，界面显示「N 个由系统锁定」。
- **外观**：主题（浅色/深色/跟随）、Liquid Glass（标准/关闭）分段开关。
- **清除本机配置**（二次确认）。

### 连接

- DDNSTO 必选，LAN HTTPS 可选；LAN 不可用自动切换 DDNSTO。
- LAN 使用固定证书 SHA-256 指纹校验。
- token 存在 Android 安全存储；不保存路由器 root 密码。

## 技术组成

- Android / Flutter 3.47+ / Dart 3.10+。
- 播放器：media_kit（libmpv）。
- 路由器侧：Lua + uhttpd CGI，无 Python 或额外运行时。

## 项目结构

```text
lib/ilink/       iLink UI、状态管理、受限网关客户端
lib/             LuCI Mobile 上游业务代码（保留复用）
gateway/         路由器 Lua 网关、ACL、安装与测试脚本
test/            上游测试与 iLink 网络、UI 测试
```

## 构建

```sh
flutter pub get
dart analyze lib test
flutter test
flutter build apk --release --split-per-abi
```

产物在 `build/app/outputs/flutter-apk/`。分发前请配置自己的签名。

本项目仅 Android：`tool/android_only_plugins/path_provider_foundation` 跳过了
Apple 专用原生构建钩子（该钩子在含空格的 Windows 用户目录下会失败）；
Android 由 `path_provider_android` 提供实现。不要用于 iOS/macOS 构建。

## 部署网关

安装会创建低权限账号、修改 rpcd 并启动网关。**请先阅读
[gateway/README.md](gateway/README.md)**，在维护窗口内手动执行脚本，脚本不会自动运行。

```sh
unzip iLink-gateway-vX.Y.Z.zip -d ilink-new
cd ilink-new/gateway && sh install.sh   # 输出手机 token，请抄好
sh test.sh                              # 校验服务与权限
```

配置概览：

1. 在路由器安装受限网关，保存安装输出的手机 token 与 LAN 证书指纹。
2. DDNSTO 域名映射到 `http://127.0.0.1:8089`，不是 LuCI 地址。
3. App 中填写 `https://<前缀>.ddnsto.com` 与 token。
4. 可选填写 `https://192.168.100.1:8443` 与证书 SHA-256 指纹。

## 安全模型

- 固定业务接口 + 白名单参数，不是通用 RPC 转发器；
- 需要特权的动作（启停服务、切配置、订阅查询、更新检查、IP 检测、
  流媒体票据、终端）经 rpcd 助手 `/usr/libexec/rpcd/ilink-action` 执行，
  ubusd ACL 只放行 `ilink` 账号；
- 文件接口限定 `/mnt/data_sdb1`，禁止路径穿越与符号链接；
- 所有写操作与危险操作在 App 内二次确认。

**终端是例外**：它等同于把 SSH 放进 App，只受设备令牌保护。令牌泄露即 root 泄露。

## 已知限制

- **视频拖动**：局域网（LAN）播放走独立流媒体进程，支持 HTTP Range，
  进度条可任意拖动；经 DDNSTO 远程播放仍走 CGI 路由，uhttpd 不转发 `Range`，
  只能缓冲区内拖动。
- **AList 下载**仍为 32MB 上限（数据经 base64 中转，无上限会打爆路由器内存）。
- 一键测速会对所有节点发真实请求，频繁使用可能触发机场限流。
- 固件「检查」比较的是系统组件版本，不是官方固件镜像版本（iStoreOS 无在线固件接口）。

## 验证

```sh
flutter test                                   # 527 项
dart format --output=none --set-exit-if-changed .
sh -n gateway/install.sh gateway/test.sh gateway/ilink.init
lua gateway/test_gateway.lua                   # 在 iStoreOS 上、仓库根目录执行
```

网关测试使用 mock RPC，不需要安装；安装后用 `gateway/test.sh` 验证真实服务与权限。
