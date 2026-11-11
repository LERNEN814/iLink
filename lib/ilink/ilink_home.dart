import 'dart:async';

import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:luci_mobile/ilink/ilink_controller.dart';
import 'package:luci_mobile/ilink/ilink_models.dart';
import 'package:luci_mobile/ilink/ilink_theme.dart';
import 'package:luci_mobile/ilink/ilink_ip_quality.dart';
import 'package:luci_mobile/ilink/ilink_network_rollback.dart';
import 'package:luci_mobile/ilink/ilink_notifications.dart';
import 'package:luci_mobile/ilink/ilink_settings.dart';
import 'package:luci_mobile/ilink/ilink_terminal.dart';
import 'package:luci_mobile/ilink/ilink_traffic.dart';
import 'package:luci_mobile/ilink/ilink_feature_api.dart';
import 'package:luci_mobile/ilink/ilink_feature_models.dart';
import 'package:luci_mobile/ilink/ilink_widgets.dart';
import 'package:luci_mobile/ilink/proxy_page.dart';
import 'package:luci_mobile/ilink/files_page.dart';

class ILinkHome extends ConsumerStatefulWidget {
  const ILinkHome({super.key});

  @override
  ConsumerState<ILinkHome> createState() => _ILinkHomeState();
}

class _ILinkHomeState extends ConsumerState<ILinkHome>
    with WidgetsBindingObserver {
  int _index = 0;

  /// -1 or 1: the direction the new tab slides in from.
  double _slideFrom = 1;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.read(iLinkProvider).refresh(silent: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      ref.read(iLinkProvider).refresh(silent: true);
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(iLinkProvider);
    final data = state.data;
    if (data == null) {
      if (state.loading) return const ILinkLoading();
      return ILinkPage(
        title: 'iLink',
        children: [
          const SizedBox(height: 70),
          ILinkMessage(state.error ?? '暂时无法获取路由器状态'),
          p.FilledButton(
            onPressed: state.loading ? null : () => state.refresh(),
            child: const Text('重新连接'),
          ),
          p.TextButton(
            onPressed: state.startEditing,
            child: const Text('检查连接设置'),
          ),
        ],
      );
    }

    final pages = <Widget>[
      const _Dashboard(),
      const ProxyPage(),
      const FilesPage(),
      const _Tools(),
    ];
    final destinations = const [
      p.NavigationDockDestination(glyph: ILinkGlyphs.dashboard, label: '概览'),
      p.NavigationDockDestination(glyph: ILinkGlyphs.proxy, label: '代理'),
      p.NavigationDockDestination(glyph: ILinkGlyphs.files, label: '文件'),
      p.NavigationDockDestination(glyph: ILinkGlyphs.tools, label: '工具'),
    ];
    return p.Surface(
      color: p.SurfaceLevel.page.colorOf(p.Theme.of(context).colorScheme),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Tabs keep their state; the switcher only animates which one is
          // visible, sliding in from the direction of travel like FlClash.
          p.BottomInsetScope(
            inset: p.NavigationDock.insetOf(context),
            child: TweenAnimationBuilder<double>(
              // Restarting from 0 on every switch slides the new tab in from
              // the side of travel instead of swapping hard.
              key: ValueKey(_index),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) => Opacity(
                opacity: t.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(_slideFrom * 24 * (1 - t), 0),
                  child: child,
                ),
              ),
              child: IndexedStack(index: _index, children: pages),
            ),
          ),
          PositionedDirectional(
            start: 0,
            end: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: p.NavigationDock(
                  destinations: destinations,
                  selectedIndex: _index,
                  onSelected: (index) => setState(() {
                    _slideFrom = index > _index ? 1 : -1;
                    _index = index;
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dashboard extends ConsumerStatefulWidget {
  const _Dashboard();

  @override
  ConsumerState<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends ConsumerState<_Dashboard> {
  bool _servicesOpen = false;
  List<ServiceState> _services = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadServices());
  }

  Future<void> _loadServices() async {
    try {
      final services = await SystemInfoService(
        ref.read(iLinkProvider).client,
      ).services();
      if (mounted) setState(() => _services = services);
    } catch (_) {
      // The card simply stays empty; the rest of the page is unaffected.
    }
  }

  bool _devicesOpen = false;
  bool _interfacesOpen = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(iLinkProvider);
    final data = state.data!;
    final memory = data.memory;
    final used =
        ((memory['total'] as num? ?? 0) - (memory['available'] as num? ?? 0));
    return ILinkPage(
      title: 'iLink',
      refreshing: state.refreshing,
      onRefresh: () => ref.read(iLinkProvider).refresh(),
      children: [
        if (state.error != null) ILinkMessage(state.error!),
        ILinkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      data.hostname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: p.AppTextStyle.title2.of(
                        context,
                        emphasized: true,
                      ),
                    ),
                  ),
                  ILinkStatusPill(data.transport),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '路由器运行正常',
                style: p.AppTextStyle.title3.of(context, emphasized: true),
              ),
              const SizedBox(height: 5),
              Text(
                '${data.model} · 已运行 ${formatUptime(data.uptime)}',
                style: p.AppTextStyle.footnote
                    .of(context)
                    .copyWith(
                      color: p.Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ILinkMetric(
                label: '内存使用',
                value: '${(data.memoryUsage * 100).round()}%',
                detail: '${formatBytes(used)} 已使用',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ILinkMetric(
                label: '系统负载',
                value: data.load.isEmpty
                    ? '—'
                    : data.load.first.toStringAsFixed(2),
                detail: '1 分钟平均负载',
              ),
            ),
          ],
        ),
        ILinkIpQualityCard(
          service: OpenClashService(ref.read(iLinkProvider).client),
        ),
        ILinkTrafficCard(
          service: SystemInfoService(ref.read(iLinkProvider).client),
        ),
        ILinkExpandableCard(
          title: '服务',
          summary: _services.isEmpty
              ? '正在读取服务状态'
              : '${_services.where((s) => s.running).length}/${_services.length} 运行中',
          expanded: _servicesOpen,
          onToggle: () {
            setState(() => _servicesOpen = !_servicesOpen);
            if (!_servicesOpen) _loadServices();
          },
          child: Column(
            children: [
              for (final service in _services)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          service.label,
                          style: p.AppTextStyle.subheadline.of(context),
                        ),
                      ),
                      ILinkStatusPill(
                        service.running ? '运行中' : '已停止',
                        online: service.running,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        ILinkExpandableCard(
          title: '设备',
          summary: data.clients.isEmpty
              ? '暂无在线设备'
              : '${data.clients.length} 台设备在线',
          expanded: _devicesOpen,
          onToggle: () => setState(() => _devicesOpen = !_devicesOpen),
          child: _Clients(embedded: true),
        ),
        ILinkExpandableCard(
          title: '网络接口',
          summary: '${data.onlineInterfaces} / ${data.interfaces.length} 个已连接',
          expanded: _interfacesOpen,
          onToggle: () => setState(() => _interfacesOpen = !_interfacesOpen),
          child: _Interfaces(embedded: true),
        ),
        const ILinkSectionTitle('系统'),
        ILinkCard(
          child: Column(
            children: [
              ILinkKeyValue('系统版本', data.release),
              ILinkKeyValue('内核', data.kernel),
              ILinkKeyValue(
                '最近更新',
                '${data.fetchedAt.hour.toString().padLeft(2, '0')}:${data.fetchedAt.minute.toString().padLeft(2, '0')}:${data.fetchedAt.second.toString().padLeft(2, '0')}',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Clients extends ConsumerWidget {
  const _Clients({this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(iLinkProvider);
    final clients = state.data!.clients;
    final children = <Widget>[
      if (!embedded) ILinkSectionTitle('${clients.length} 台设备'),
      if (clients.isEmpty)
        const ILinkEmpty('暂未发现客户端')
      else
        for (final client in clients)
          ILinkCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        client.hostname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: p.AppTextStyle.headline.of(context),
                      ),
                    ),
                    ILinkStatusPill(client.connectionLabel),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  client.ipAddress,
                  style: p.AppTextStyle.subheadline.of(context),
                ),
                const SizedBox(height: 5),
                Text(
                  [
                    client.macAddress,
                    if (client.vendor?.isNotEmpty == true) client.vendor!,
                  ].join(' · '),
                  style: p.AppTextStyle.caption1
                      .of(context)
                      .copyWith(
                        color: p.Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
    ];
    if (embedded) return Column(children: children);
    return ILinkPage(
      title: '客户端',
      refreshing: state.refreshing,
      onRefresh: () => ref.read(iLinkProvider).refresh(),
      children: children,
    );
  }
}

class _Interfaces extends ConsumerWidget {
  const _Interfaces({this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(iLinkProvider);
    final interfaces = state.data!.interfaces;
    final children = <Widget>[
      if (interfaces.isEmpty)
        const ILinkEmpty('未获取到网络接口')
      else
        for (final interface in interfaces)
          ILinkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        interface.name,
                        style: p.AppTextStyle.headline.of(context),
                      ),
                    ),
                    ILinkStatusPill(
                      interface.isUp ? '已连接' : '未连接',
                      online: interface.isUp,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ILinkKeyValue('IPv4', interface.ipAddress ?? '—'),
                ILinkKeyValue('协议', interface.protocol),
                ILinkKeyValue('设备', interface.device),
                ILinkKeyValue('网关', interface.gateway ?? '—'),
              ],
            ),
          ),
    ];
    if (embedded) return Column(children: children);
    return ILinkPage(
      title: '网络接口',
      refreshing: state.refreshing,
      onRefresh: () => ref.read(iLinkProvider).refresh(),
      children: children,
    );
  }
}

class _Tools extends ConsumerStatefulWidget {
  const _Tools();

  @override
  ConsumerState<_Tools> createState() => _ToolsState();
}

class _ToolsState extends ConsumerState<_Tools> {
  final TextEditingController _link = TextEditingController();
  List<DownloadJob> _jobs = const [];
  List<String> _updates = const [];
  int _pinnedUpdates = 0;
  bool _checkingFirmware = false;
  FirmwareInfo? _firmware;
  String? _firmwareNote;
  bool _downloading = false;
  bool _checkingUpdates = false;
  bool _upgrading = false;
  String _upgradeState = 'idle';
  List<String> _upgradeLog = const [];
  String? _downloadNote;
  FastNetResult? _fastNet;
  String? _fastNetLabel;
  bool _fastNetBusy = false;

  Future<void> _refreshJobs() async {
    try {
      final jobs = await DownloaderService(
        ref.read(iLinkProvider).client,
      ).jobs();
      if (mounted) setState(() => _jobs = jobs);
    } catch (error) {
      if (mounted) setState(() => _downloadNote = error.toString());
    }
  }

  Future<void> _submitLink() async {
    final url = _link.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _downloading = true;
      _downloadNote = null;
    });
    try {
      final kind = await DownloaderService(
        ref.read(iLinkProvider).client,
      ).submit(url);
      _link.clear();
      if (mounted) {
        setState(
          () => _downloadNote = kind == 'torrent'
              ? '已提交到 qBittorrent'
              : '已开始解析并下载到 video 目录',
        );
      }
      await _refreshJobs();
    } catch (error) {
      if (mounted) setState(() => _downloadNote = error.toString());
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _openTerminal() async {
    if (!await confirmTerminal(context)) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ILinkTerminalPage(
          service: SystemInfoService(ref.read(iLinkProvider).client),
        ),
      ),
    );
  }

  Future<void> _checkFirmware() async {
    setState(() => _checkingFirmware = true);
    try {
      final info = await SystemInfoService(
        ref.read(iLinkProvider).client,
      ).firmware();
      if (!mounted) return;
      setState(() {
        _firmware = info;
        _firmwareNote = info.available.isEmpty
            ? '当前 ${info.release} 已是最新'
            : '有 ${info.available.length} 个基础组件新版本，需在网页端更新';
      });
    } catch (error) {
      if (mounted) setState(() => _firmwareNote = error.toString());
    } finally {
      if (mounted) setState(() => _checkingFirmware = false);
    }
  }

  Future<void> _openLuCiFlash() async {
    final uri = Uri.parse(
      'http://192.168.100.1/cgi-bin/luci/admin/system/flash',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _startUpgrade() async {
    final confirmed = await p.showFloatingDialog<bool>(
      context: context,
      child: p.AlertDialog(
        title: '更新全部应用？',
        destructive: true,
        actions: [
          p.TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          p.TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('开始更新'),
          ),
        ],
        child: Text(
          '将升级 ${_updates.length} 个软件包，期间网络可能短暂波动；'
          '正在运行的服务会在完成后自动重启。固件不会被动到。',
        ),
      ),
    );
    if (confirmed != true) return;
    const noticeId = 4099;
    const notifier = TransferNotifier();
    setState(() {
      _upgrading = true;
      _upgradeState = 'running';
      _upgradeLog = const [];
    });
    try {
      await SystemInfoService(ref.read(iLinkProvider).client).startUpgrade();
      unawaited(
        notifier.progress(
          id: noticeId,
          title: '正在更新应用',
          text: '${_updates.length} 个软件包',
          fraction: 0.5,
        ),
      );
      await _pollUpgrade(noticeId: noticeId, notifier: notifier);
    } catch (error) {
      unawaited(
        notifier.done(
          id: noticeId,
          title: '更新失败',
          text: error.toString(),
          failed: true,
        ),
      );
      if (mounted) {
        setState(() {
          _upgrading = false;
          _upgradeState = 'error';
          _upgradeLog = [error.toString()];
        });
      }
    }
  }

  Future<void> _pollUpgrade({
    required int noticeId,
    required TransferNotifier notifier,
  }) async {
    for (var attempt = 0; attempt < 120; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 5));
      if (!mounted) return;
      try {
        final status = await SystemInfoService(
          ref.read(iLinkProvider).client,
        ).upgradeStatus();
        if (!mounted) return;
        setState(() {
          _upgradeState = status.state;
          _upgradeLog = status.tail;
        });
        if (status.state != 'running') break;
      } catch (_) {
        // The router may bounce during the upgrade; keep polling.
      }
    }
    unawaited(
      notifier.done(
        id: noticeId,
        title: _upgradeState == 'error' ? '更新失败' : '应用更新完成',
        text: _upgradeState == 'error'
            ? (_upgradeLog.isEmpty ? '见路由器日志' : _upgradeLog.last)
            : '服务已按需重启',
        failed: _upgradeState == 'error',
      ),
    );
    if (!mounted) return;
    setState(() => _upgrading = false);
    await _checkUpdates();
  }

  Future<void> _checkUpdates() async {
    setState(() => _checkingUpdates = true);
    try {
      final check = await SystemInfoService(
        ref.read(iLinkProvider).client,
      ).updates();
      if (mounted) {
        setState(() {
          _updates = check.packages;
          _pinnedUpdates = check.pinned;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _downloadNote = error.toString());
    } finally {
      if (mounted) setState(() => _checkingUpdates = false);
    }
  }

  Future<void> _runFastNet(String kind) async {
    final service = FastNetService(ref.read(iLinkProvider).client);
    setState(() {
      _fastNetBusy = true;
      _fastNetLabel = switch (kind) {
        'nat' => 'NAT 检测',
        'ipv6' => 'IPv6 检测',
        _ => '快速体检',
      };
      _fastNet = null;
    });
    try {
      final result = switch (kind) {
        'nat' => await service.nat(),
        'ipv6' => await service.ipv6(),
        _ => await service.quick(),
      };
      if (mounted) setState(() => _fastNet = result);
    } catch (error) {
      if (mounted) {
        setState(
          () => _fastNet = FastNetResult(
            summary: {'error': error.toString()},
            logs: const [],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _fastNetBusy = false);
    }
  }

  Widget _fastNetCard() {
    final result = _fastNet;
    final summary = result?.summary ?? const <String, dynamic>{};
    final ping = (summary['pingMs'] as num?)?.toStringAsFixed(1);
    final jitter = (summary['jitterMs'] as num?)?.toStringAsFixed(1);
    final down = (summary['downloadBps'] as num?)?.toDouble();
    final up = (summary['uploadBps'] as num?)?.toDouble();
    return ILinkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('网络体检', style: p.AppTextStyle.headline.of(context)),
          const SizedBox(height: 6),
          Text(
            '在路由器上测速，会短暂占用带宽并消耗流量。',
            style: p.AppTextStyle.caption1
                .of(context)
                .copyWith(
                  color: p.Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: p.OutlinedButton(
                  onPressed: _fastNetBusy ? null : () => _runFastNet('quick'),
                  child: const Text('快速体检'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: p.OutlinedButton(
                  onPressed: _fastNetBusy ? null : () => _runFastNet('nat'),
                  child: const Text('NAT'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: p.OutlinedButton(
                  onPressed: _fastNetBusy ? null : () => _runFastNet('ipv6'),
                  child: const Text('IPv6'),
                ),
              ),
            ],
          ),
          if (_fastNetBusy) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const p.ActivityIndicator(size: 18),
                const SizedBox(width: 10),
                Text(
                  '正在执行${_fastNetLabel ?? '检测'}…',
                  style: p.AppTextStyle.footnote.of(context),
                ),
              ],
            ),
          ],
          if (result != null) ...[
            const SizedBox(height: 12),
            if (ping != null) ILinkKeyValue('延迟', '$ping ms（抖动 $jitter ms）'),
            if (down != null) ILinkKeyValue('下载', '${formatBytes(down / 8)}/s'),
            if (up != null) ILinkKeyValue('上传', '${formatBytes(up / 8)}/s'),
            for (final entry in summary.entries)
              if (!const {
                'pingMs',
                'jitterMs',
                'downloadBps',
                'uploadBps',
              }.contains(entry.key))
                ILinkKeyValue(entry.key, '${entry.value}'),
            if (result.logs.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: ShapeDecoration(
                  color: p.SurfaceLevel.inset.colorOf(
                    p.Theme.of(context).colorScheme,
                  ),
                  shape: p.AppShape.all(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in result.logs.reversed.take(6))
                      Text(
                        line,
                        style: p.AppTextStyle.caption1
                            .of(context)
                            .copyWith(
                              color: p.Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(iLinkProvider);
    final data = state.data!;
    return ILinkPage(
      title: '工具',
      refreshing: state.refreshing,
      onRefresh: () => ref.read(iLinkProvider).refresh(),
      action: p.AppBarActionButton(
        data: p.IconButtonData(
          glyph: ILinkGlyphs.settings,
          tooltip: '设置',
          onPressed: () => openSettings(context),
        ),
      ),
      children: [
        const ILinkSectionTitle('连接'),
        ILinkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ILinkKeyValue('当前通道', data.transport),
              ILinkKeyValue('远程地址', state.profile!.remoteUrl),
              ILinkKeyValue(
                '局域网',
                state.profile!.lanUrl.isEmpty ? '未配置' : state.profile!.lanUrl,
              ),
              ILinkKeyValue('安全', '独立设备凭据 · 固定业务接口'),
              const SizedBox(height: 12),
              p.OutlinedButton(
                onPressed: state.startEditing,
                child: const Text('修改连接设置'),
              ),
            ],
          ),
        ),
        const ILinkSectionTitle('下载'),
        ILinkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              p.TextFormField(
                controller: _link,
                decoration: const p.InputDecoration(
                  hintText: '粘贴视频链接、m3u8、磁链或 .torrent',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: p.FilledButton(
                      onPressed: _downloading ? null : _submitLink,
                      child: Text(_downloading ? '提交中…' : '发送下载'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  p.OutlinedButton(
                    onPressed: _refreshJobs,
                    child: const Text('刷新'),
                  ),
                ],
              ),
              if (_downloadNote != null) ...[
                const SizedBox(height: 8),
                Text(
                  _downloadNote!,
                  style: p.AppTextStyle.caption1
                      .of(context)
                      .copyWith(
                        color: p.Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
              for (final job in _jobs.take(8))
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              job.name.isEmpty ? job.id : job.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: p.AppTextStyle.footnote.of(context),
                            ),
                          ),
                          p.TextButton(
                            onPressed: () async {
                              await DownloaderService(
                                ref.read(iLinkProvider).client,
                              ).remove(job);
                              await _refreshJobs();
                            },
                            child: const Text('移除'),
                          ),
                        ],
                      ),
                      p.LinearProgressIndicator(
                        value: job.progress.clamp(0, 1),
                        minHeight: 4,
                        backgroundColor: p.Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                      if (job.detail.isNotEmpty)
                        Text(
                          '${job.state} · ${job.detail}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: p.AppTextStyle.caption1
                              .of(context)
                              .copyWith(
                                color: p.Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const ILinkSectionTitle('终端'),
        ILinkTerminalTile(onTap: _openTerminal),
        const ILinkSectionTitle('网络配置回滚'),
        const ILinkNetworkRollbackCard(),
        const ILinkSectionTitle('网络体检'),
        _fastNetCard(),
        const ILinkSectionTitle('固件与应用更新'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ILinkCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('固件', style: p.AppTextStyle.headline.of(context)),
                    const SizedBox(height: 6),
                    Text(
                      _firmware?.release ?? data.release,
                      style: p.AppTextStyle.caption1
                          .of(context)
                          .copyWith(
                            color: p.Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    p.OutlinedButton(
                      onPressed: _checkingFirmware ? null : _checkFirmware,
                      child: Text(_checkingFirmware ? '检查中…' : '检查固件更新'),
                    ),
                    const SizedBox(height: 8),
                    p.OutlinedButton(
                      onPressed: _openLuCiFlash,
                      child: const Text('打开固件升级'),
                    ),
                    if (_firmwareNote != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _firmwareNote!,
                          style: p.AppTextStyle.caption1
                              .of(context)
                              .copyWith(
                                color: p.Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      '刷写固件在系统浏览器中完成；应用只检查系统组件版本。',
                      style: p.AppTextStyle.caption1
                          .of(context)
                          .copyWith(
                            color: p.Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ILinkCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('应用', style: p.AppTextStyle.headline.of(context)),
                    const SizedBox(height: 6),
                    Text(
                      _updates.isEmpty
                          ? (_pinnedUpdates > 0
                                ? '$_pinnedUpdates 个由系统锁定'
                                : '尚未检查')
                          : '${_updates.length} 个可更新',
                      style: p.AppTextStyle.caption1
                          .of(context)
                          .copyWith(
                            color: p.Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    p.OutlinedButton(
                      onPressed: _checkingUpdates || _upgrading
                          ? null
                          : _checkUpdates,
                      child: Text(_checkingUpdates ? '检查中…' : '检查更新'),
                    ),
                    const SizedBox(height: 8),
                    p.OutlinedButton(
                      onPressed: _upgrading || _updates.isEmpty
                          ? null
                          : _startUpgrade,
                      child: Text(_upgrading ? '更新中…' : '一键更新'),
                    ),
                    if (_upgrading || _upgradeState != 'idle')
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          switch (_upgradeState) {
                            'done' => '更新完成',
                            'error' => '更新失败，请查看路由器日志',
                            'running' => '正在更新，请勿断电',
                            _ => '准备中',
                          },
                          style: p.AppTextStyle.caption1
                              .of(context)
                              .copyWith(
                                color: _upgradeState == 'error'
                                    ? p.Theme.of(context).colorScheme.error
                                    : p.Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    if (_upgradeLog.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _upgradeLog.last,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: p.AppTextStyle.caption1
                              .of(context)
                              .copyWith(
                                color: p.Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
