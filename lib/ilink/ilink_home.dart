import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:luci_mobile/ilink/ilink_controller.dart';
import 'package:luci_mobile/ilink/ilink_models.dart';
import 'package:luci_mobile/ilink/ilink_theme.dart';
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
          // Every tab keeps its state: switching back must not refetch or
          // reset scroll position.
          p.BottomInsetScope(
            inset: p.NavigationDock.insetOf(context),
            child: IndexedStack(index: _index, children: pages),
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
                  onSelected: (index) => setState(() => _index = index),
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
  bool _devicesOpen = false;
  bool _wifiOpen = false;
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
          title: '无线网络',
          summary: data.wireless.isEmpty
              ? '未启用无线'
              : data.wireless.map((w) => w.ssid).join('、'),
          expanded: _wifiOpen,
          onToggle: () => setState(() => _wifiOpen = !_wifiOpen),
          child: _Wireless(embedded: true),
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
              ILinkKeyValue('无线网络', '${data.wireless.length} 个'),
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

class _Wireless extends ConsumerWidget {
  const _Wireless({this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(iLinkProvider);
    final wireless = state.data!.wireless;
    final children = <Widget>[
      if (wireless.isEmpty)
        const ILinkEmpty('未获取到无线网络信息')
      else
        for (final wifi in wireless)
          ILinkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        wifi.ssid,
                        style: p.AppTextStyle.headline.of(context),
                      ),
                    ),
                    ILinkStatusPill(wifi.up ? '已启用' : '已停用', online: wifi.up),
                  ],
                ),
                const SizedBox(height: 10),
                ILinkKeyValue('射频', wifi.radio),
                ILinkKeyValue('模式', wifi.mode),
                ILinkKeyValue(
                  '频段 / 信道',
                  '${wifi.band.isEmpty ? '—' : wifi.band} / ${wifi.channel == 0 ? '自动' : wifi.channel}',
                ),
                ILinkKeyValue(
                  '加密',
                  wifi.encryption.isEmpty ? '—' : wifi.encryption,
                ),
              ],
            ),
          ),
    ];
    if (embedded) return Column(children: children);
    return ILinkPage(
      title: '无线网络',
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
  bool _confirmClear = false;
  FastNetResult? _fastNet;
  String? _fastNetLabel;
  bool _fastNetBusy = false;

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
    final themeLabel = switch (state.themeIndex) {
      1 => '浅色',
      2 => '深色',
      _ => '跟随系统',
    };
    return ILinkPage(
      title: '工具',
      refreshing: state.refreshing,
      onRefresh: () => ref.read(iLinkProvider).refresh(),
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
        const ILinkSectionTitle('网络体检'),
        _fastNetCard(),
        const ILinkSectionTitle('外观'),
        ILinkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              p.OutlinedButton(
                onPressed: state.cycleTheme,
                child: Text('主题：$themeLabel'),
              ),
              const SizedBox(height: 8),
              p.OutlinedButton(
                onPressed: state.toggleGlass,
                child: Text('Liquid Glass：${state.glassEnabled ? '标准' : '关闭'}'),
              ),
            ],
          ),
        ),
        const ILinkSectionTitle('本机配置'),
        ILinkCard(
          child: _confirmClear
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '清除本机保存的地址与设备凭据？路由器上的凭据仍然有效，可单独撤销。',
                      style: p.AppTextStyle.footnote.of(context),
                    ),
                    const SizedBox(height: 16),
                    p.FilledButton(
                      onPressed: state.clear,
                      child: const Text('确认清除'),
                    ),
                    p.TextButton(
                      onPressed: () => setState(() => _confirmClear = false),
                      child: const Text('取消'),
                    ),
                  ],
                )
              : p.OutlinedButton(
                  onPressed: () => setState(() => _confirmClear = true),
                  child: const Text('清除本机配置'),
                ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'iLink v0.5.0\n基于 LuCI Mobile 与 Prism UI · GPL-3.0\n固定业务接口 · 最小权限',
            textAlign: TextAlign.center,
            style: p.AppTextStyle.caption1
                .of(context)
                .copyWith(
                  color: p.Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }
}
