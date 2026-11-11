import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/ilink/ilink_api.dart';
import 'package:luci_mobile/ilink/ilink_controller.dart';
import 'package:luci_mobile/ilink/ilink_feature_api.dart';
import 'package:luci_mobile/ilink/ilink_widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;

/// Snapshots of /etc/config/network with a watchdog restore. Restoring can cut
/// the link this phone is using, so the router reverts on its own unless the
/// restore is confirmed within the window.
class ILinkNetworkRollbackCard extends ConsumerStatefulWidget {
  const ILinkNetworkRollbackCard({super.key});

  @override
  ConsumerState<ILinkNetworkRollbackCard> createState() =>
      _ILinkNetworkRollbackCardState();
}

class _ILinkNetworkRollbackCardState
    extends ConsumerState<ILinkNetworkRollbackCard> {
  List<({String name, DateTime modified})> _backups = const [];
  bool _loading = false;
  String? _error;
  String? _pendingRestore;
  int _window = 120;

  SystemInfoService get _service =>
      SystemInfoService(ref.read(iLinkProvider).client);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await _service.networkBackups();
      if (!mounted) return;
      setState(() {
        _backups = result.backups;
        _window = result.window;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _snapshot() async {
    setState(() => _loading = true);
    try {
      await _service.networkSnapshot();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restore(String name) async {
    final confirmed = await p.showFloatingDialog<bool>(
      context: context,
      child: p.AlertDialog(
        title: '恢复网络配置？',
        destructive: true,
        actions: [
          p.TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          p.TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('恢复'),
          ),
        ],
        child: Text(
          '将用 $name 覆盖当前网络配置并重载网络。'
          '如果 $_window 秒内没有点「保持」，路由器会自动恢复原配置；'
          '期间手机与路由器可能断开连接。',
        ),
      ),
    );
    if (confirmed != true) return;
    setState(() => _loading = true);
    try {
      await _service.networkRestore(name);
      if (!mounted) return;
      setState(() => _pendingRestore = name);
    } on ILinkApiException catch (error) {
      // A timeout here is expected when the link drops; the watchdog still runs.
      if (mounted) setState(() => _pendingRestore = name);
      if (!error.isAuthentication && mounted) {
        setState(() => _error = null);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    try {
      await _service.networkConfirm();
      if (mounted) setState(() => _pendingRestore = null);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  static String _format(DateTime time) =>
      '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final muted = p.Theme.of(context).colorScheme.onSurfaceVariant;
    return ILinkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '修改网络配置后如果连不上路由器，这里可以退回上一个快照。',
            style: p.AppTextStyle.caption1.of(context).copyWith(color: muted),
          ),
          if (_pendingRestore != null) ...[
            const SizedBox(height: 12),
            Text(
              '已恢复 $_pendingRestore。确认网络正常后点「保持」，'
              '否则 $_window 秒后自动回滚。',
              style: p.AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: p.Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 8),
            p.FilledButton(onPressed: _confirm, child: const Text('保持当前配置')),
          ],
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: p.AppTextStyle.caption1
                    .of(context)
                    .copyWith(color: p.Theme.of(context).colorScheme.error),
              ),
            ),
          if (_backups.isEmpty)
            Text(
              _loading ? '正在读取…' : '还没有快照',
              style: p.AppTextStyle.caption1.of(context).copyWith(color: muted),
            )
          else
            for (final backup in _backups)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _format(backup.modified),
                        style: p.AppTextStyle.subheadline.of(context),
                      ),
                    ),
                    p.TextButton(
                      onPressed: _loading ? null : () => _restore(backup.name),
                      child: const Text('恢复'),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 8),
          p.OutlinedButton(
            onPressed: _loading ? null : _snapshot,
            child: const Text('给当前配置拍快照'),
          ),
        ],
      ),
    );
  }
}
