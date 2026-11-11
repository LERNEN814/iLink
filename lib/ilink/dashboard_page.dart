import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/ilink/ilink_controller.dart';
import 'package:luci_mobile/ilink/ilink_feature_api.dart';
import 'package:luci_mobile/ilink/ilink_feature_models.dart';
import 'package:luci_mobile/ilink/ilink_ip_quality.dart';
import 'package:luci_mobile/ilink/ilink_models.dart';
import 'package:luci_mobile/ilink/ilink_traffic.dart';
import 'package:luci_mobile/ilink/ilink_widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardState();
}

class _DashboardState extends ConsumerState<DashboardPage> {
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
