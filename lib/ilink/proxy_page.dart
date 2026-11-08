import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:luci_mobile/ilink/ilink_controller.dart';
import 'package:luci_mobile/ilink/ilink_feature_api.dart';
import 'package:luci_mobile/ilink/ilink_feature_models.dart';
import 'package:luci_mobile/ilink/ilink_models.dart';
import 'package:luci_mobile/ilink/ilink_widgets.dart';

class ProxyPage extends ConsumerStatefulWidget {
  const ProxyPage({super.key, this.service});

  /// Injected in tests; production builds use the gateway client.
  final OpenClashService? service;

  @override
  ConsumerState<ProxyPage> createState() => _ProxyPageState();
}

class _ProxyPageState extends ConsumerState<ProxyPage> {
  late final OpenClashService _service;
  OpenClashData? _data;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  int _tab = 0;
  int _groupIndex = 0;
  final Map<String, int> _delays = {};
  final Set<String> _testing = {};

  @override
  void initState() {
    super.initState();
    _service =
        widget.service ?? OpenClashService(ref.read(iLinkProvider).client);
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final data = await _service.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test(ProxyNode node) async {
    if (_testing.contains(node.name)) return;
    setState(() => _testing.add(node.name));
    try {
      final delay = await _service.testDelay(node.name);
      if (mounted) setState(() => _delays[node.name] = delay);
    } catch (_) {
      if (mounted) setState(() => _delays[node.name] = -1);
    } finally {
      if (mounted) setState(() => _testing.remove(node.name));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return ILinkPage(
      title: '代理',
      refreshing: _loading,
      onRefresh: _busy ? null : _refresh,
      children: [
        if (_error != null) ILinkMessage(_error!),
        if (data == null)
          _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 80),
                  child: Center(child: p.ActivityIndicator()),
                )
              : const ILinkEmpty('连接 OpenClash 后查看代理信息')
        else ...[
          ILinkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'OpenClash',
                        style: p.AppTextStyle.title3.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                    ),
                    ILinkStatusPill(
                      data.running ? '运行中' : '已停止',
                      online: data.running,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ILinkKeyValue('配置文件', data.configName),
                ILinkKeyValue('核心', data.version),
                ILinkKeyValue('模式', data.mode.toUpperCase()),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ILinkMetric(
                        label: '活跃连接',
                        value: '${data.connections.length}',
                      ),
                    ),
                    Expanded(
                      child: ILinkMetric(
                        label: '下载',
                        value: formatBytes(data.download),
                      ),
                    ),
                    Expanded(
                      child: ILinkMetric(
                        label: '上传',
                        value: formatBytes(data.upload),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          p.SegmentedControl<int>(
            segments: const [(0, '代理'), (1, '连接'), (2, '配置')],
            value: _tab,
            onChanged: (value) => setState(() => _tab = value),
          ),
          const SizedBox(height: 14),
          if (_tab == 0) _buildGroups(data),
          if (_tab == 1) _buildConnections(data),
          if (_tab == 2) _buildConfig(data),
        ],
      ],
    );
  }

  Widget _buildGroups(OpenClashData data) {
    if (data.groups.isEmpty) return const ILinkEmpty('暂无代理组');
    _groupIndex = _groupIndex.clamp(0, data.groups.length - 1);
    final group = data.groups[_groupIndex];
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: data.groups.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) => p.Chip(
              label: data.groups[index].name,
              selected: _groupIndex == index,
              onPressed: () => setState(() => _groupIndex = index),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ILinkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(group.name, style: p.AppTextStyle.headline.of(context)),
              const SizedBox(height: 4),
              Text(
                '${group.type} · 当前 ${group.now}',
                style: p.AppTextStyle.footnote
                    .of(context)
                    .copyWith(
                      color: p.Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.1,
          ),
          itemCount: group.nodes.length,
          itemBuilder: (context, index) {
            final node = group.nodes[index];
            final selected = group.now == node.name;
            final delay =
                _delays[node.name] ?? (node.delay > 0 ? node.delay : null);
            final scheme = p.Theme.of(context).colorScheme;
            final delayColor = delay == null || delay == 0
                ? scheme.onSurfaceVariant
                : delay < 0 || delay > 800
                ? scheme.error
                : delay < 350
                ? scheme.success
                : scheme.warning;
            return p.PressSurface(
              fill: selected
                  ? scheme.primary.withValues(alpha: 0.12)
                  : p.SurfaceLevel.card.colorOf(scheme),
              shape: p.AppShape.all(24),
              onPressed: _busy || group.type != 'Selector'
                  ? null
                  : () => _run(() => _service.select(group.name, node.name)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            node.type,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: p.AppTextStyle.caption1
                                .of(context)
                                .copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                        if (selected)
                          Text('✓', style: TextStyle(color: scheme.primary)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Text(
                        node.name,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: p.AppTextStyle.footnote.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _test(node),
                      child: Text(
                        _testing.contains(node.name)
                            ? '测试中…'
                            : delay == null || delay == 0
                            ? '点击测速'
                            : delay < 0
                            ? '不可用'
                            : '$delay ms',
                        style: p.AppTextStyle.caption1
                            .of(context, emphasized: true)
                            .copyWith(color: delayColor),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildConnections(OpenClashData data) {
    if (data.connections.isEmpty) return const ILinkEmpty('暂无活跃连接');
    return Column(
      children: [
        for (final connection in data.connections)
          ILinkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connection.host.isEmpty ? '未知目标' : connection.host,
                  style: p.AppTextStyle.subheadline.of(
                    context,
                    emphasized: true,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${connection.rule} · ${connection.chain.join(' → ')}',
                  style: p.AppTextStyle.caption1
                      .of(context)
                      .copyWith(
                        color: p.Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '↑ ${formatBytes(connection.upload)}  ↓ ${formatBytes(connection.download)}',
                        style: p.AppTextStyle.caption1.of(context),
                      ),
                    ),
                    p.TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() => _service.close(connection.id)),
                      child: const Text('断开'),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildConfig(OpenClashData data) => ILinkCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('当前配置', style: p.AppTextStyle.headline.of(context)),
        const SizedBox(height: 10),
        Text(data.configName, style: p.AppTextStyle.body.of(context)),
        const SizedBox(height: 8),
        Text(
          '节点切换通过 Mihomo 控制器完成，不重写订阅文件。订阅编辑与配置切换将在 v0.3 提供。',
          style: p.AppTextStyle.footnote
              .of(context)
              .copyWith(
                color: p.Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        ILinkKeyValue('累计下载', formatBytes(data.downloadTotal)),
        ILinkKeyValue('累计上传', formatBytes(data.uploadTotal)),
        ILinkKeyValue('混合端口', '${data.mixedPort}'),
      ],
    ),
  );
}
