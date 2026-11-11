import 'dart:async';

import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/ilink/ilink_controller.dart';
import 'package:luci_mobile/ilink/ilink_feature_api.dart';
import 'package:luci_mobile/ilink/ilink_feature_models.dart';
import 'package:luci_mobile/ilink/ilink_models.dart';
import 'package:luci_mobile/ilink/ilink_notifications.dart';
import 'package:luci_mobile/ilink/ilink_settings.dart';
import 'package:luci_mobile/ilink/ilink_terminal.dart';
import 'package:luci_mobile/ilink/ilink_widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:url_launcher/url_launcher.dart';

class ToolsPage extends ConsumerStatefulWidget {
  const ToolsPage({super.key});

  @override
  ConsumerState<ToolsPage> createState() => _ToolsState();
}

class _ToolsState extends ConsumerState<ToolsPage> {
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
      children: [
        ILinkSettingsBar(onTap: () => openSettings(context)),
        const ILinkSectionTitle('终端'),
        ILinkTerminalTile(onTap: _openTerminal),
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
