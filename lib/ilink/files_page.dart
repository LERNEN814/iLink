import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:prism_ui/icons/glyph.dart';
import 'package:luci_mobile/ilink/ilink_controller.dart';
import 'package:luci_mobile/ilink/ilink_feature_api.dart';
import 'package:luci_mobile/ilink/ilink_feature_models.dart';
import 'package:luci_mobile/ilink/ilink_models.dart';
import 'package:luci_mobile/ilink/ilink_widgets.dart';

class FilesPage extends ConsumerStatefulWidget {
  const FilesPage({super.key, this.service});

  /// Injected in tests; production builds use the gateway client.
  final FileService? service;

  @override
  ConsumerState<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends ConsumerState<FilesPage> {
  late final FileService _service;
  final TextEditingController _search = TextEditingController();
  final Set<String> _history = {};
  List<FileEntry> _entries = [];
  String _path = '';
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _descending = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? FileService(ref.read(iLinkProvider).client);
    _refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final entries = await _service.list(_path);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
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

  void _open(FileEntry entry) {
    if (entry.directory) {
      setState(() {
        _history.add(_path);
        _path = entry.path;
        _search.clear();
      });
      _refresh();
    } else {
      _download(entry);
    }
  }

  Future<void> _back() async {
    if (_history.isEmpty) return;
    setState(() => _path = _history.last);
    _history.remove(_history.last);
    await _refresh();
  }

  Future<void> _download(FileEntry entry) async {
    if (entry.size > 32 * 1024 * 1024) {
      setState(() => _error = 'v0.2 下载上限为 32 MB；大文件传输任务将在后续版本提供');
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await _service.download(entry.path);
      final directory = await getApplicationDocumentsDirectory();
      var target = File('${directory.path}/${entry.name}');
      var suffix = 1;
      while (await target.exists()) {
        final dot = entry.name.lastIndexOf('.');
        final stem = dot > 0 ? entry.name.substring(0, dot) : entry.name;
        final extension = dot > 0 ? entry.name.substring(dot) : '';
        target = File('${directory.path}/$stem ($suffix)$extension');
        suffix++;
      }
      await target.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      await p.showFloatingDialog<void>(
        context: context,
        child: p.AlertDialog(
          title: '已保存到应用文档目录',
          actions: [
            p.TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
          child: Text('${target.path}\n${formatBytes(bytes.length)}'),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _nameDialog({FileEntry? entry}) async {
    final controller = TextEditingController(text: entry?.name ?? '');
    final name = await p.showFloatingDialog<String>(
      context: context,
      child: p.InputDialog(
        title: entry == null ? '新建文件夹' : '重命名',
        value: controller.text,
        labelText: '名称',
        validator: (value) {
          final name = value?.trim() ?? '';
          if (name.isEmpty || name.contains('/') || name.contains('\\')) {
            return '请输入有效名称';
          }
          return null;
        },
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    await _run(
      () => entry == null
          ? _service.mkdir(_path, name.trim())
          : _service.rename(entry.path, name.trim()),
    );
  }

  Future<void> _delete(FileEntry entry) async {
    final confirmed = await p.showFloatingDialog<bool>(
      context: context,
      child: p.AlertDialog(
        title: '删除${entry.directory ? '文件夹' : '文件'}？',
        destructive: true,
        actions: [
          p.TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          p.TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
        child: Text('${entry.name}\n只能删除空文件夹，此操作不可撤销。'),
      ),
    );
    if (confirmed == true) await _run(() => _service.remove(entry.path));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(iLinkProvider);
    final query = _search.text.trim().toLowerCase();
    final entries = _entries
        .where((entry) => entry.name.toLowerCase().contains(query))
        .toList();
    entries.sort((a, b) {
      if (a.directory != b.directory) return a.directory ? -1 : 1;
      final result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return _descending ? -result : result;
    });
    final mounts = state.data?.status['mounts'] as List? ?? const [];
    final storage = mounts.whereType<Map>().firstWhere(
      (item) => item['mount'] == '/mnt/data_sdb1',
      orElse: () => const {},
    );
    final size = storage['size'] as num?;
    final available = storage['available'] as num?;
    return ILinkPage(
      title: '文件',
      refreshing: _loading,
      onRefresh: _busy ? null : _refresh,
      children: [
        Row(
          children: [
            if (_path.isNotEmpty)
              p.TextButton(onPressed: _back, child: const Text('‹ 上级')),
            Expanded(
              child: Text(
                '/mnt/data_sdb1${_path.isEmpty ? '' : '/$_path'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: p.AppTextStyle.footnote
                    .of(context)
                    .copyWith(
                      color: p.Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        p.TextFormField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const p.InputDecoration(hintText: '搜索当前目录', filled: true),
        ),
        const SizedBox(height: 12),
        ILinkCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  size == null
                      ? '共享存储'
                      : '可用 ${formatBytes(available)} / 共 ${formatBytes(size)}',
                  style: p.AppTextStyle.footnote.of(context),
                ),
              ),
              p.TextButton(
                onPressed: () => _nameDialog(),
                child: const Text('新建文件夹'),
              ),
            ],
          ),
        ),
        if (_error != null) ILinkMessage(_error!),
        Row(
          children: [
            Expanded(
              child: Text(
                '${entries.length} 项',
                style: p.AppTextStyle.footnote.of(context),
              ),
            ),
            p.TextButton(
              onPressed: () => setState(() => _descending = !_descending),
              child: Text(_descending ? '名称 ↓' : '名称 ↑'),
            ),
          ],
        ),
        if (_loading && _entries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: p.ActivityIndicator()),
          )
        else if (entries.isEmpty)
          const ILinkEmpty('此目录为空')
        else
          for (final entry in entries)
            p.ContextMenuRegion(
              menuItems: [
                p.PopupMenuItem(
                  glyph: _editGlyph,
                  label: '重命名',
                  onPressed: () => _nameDialog(entry: entry),
                ),
                p.PopupMenuItem(
                  glyph: _deleteGlyph,
                  label: '删除',
                  onPressed: () => _delete(entry),
                ),
              ],
              child: ILinkCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: p.PressSurface(
                  fill: const Color(0x00000000),
                  shape: p.AppShape.all(18),
                  onPressed: _busy ? null : () => _open(entry),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Text(
                          entry.directory ? '▰' : '▱',
                          style: TextStyle(
                            fontSize: 24,
                            color: p.Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: p.AppTextStyle.subheadline.of(
                                  context,
                                  emphasized: true,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                entry.directory
                                    ? '文件夹'
                                    : formatBytes(entry.size),
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
                        if (_busy)
                          const p.ActivityIndicator(size: 18)
                        else
                          Text(entry.directory ? '›' : '↓'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        const SizedBox(height: 8),
        Text(
          '仅限共享目录 /mnt/data_sdb1。长按文件可重命名或删除；禁止系统目录、路径穿越和符号链接。上传与预览将在 v0.3 提供。',
          textAlign: TextAlign.center,
          style: p.AppTextStyle.caption1
              .of(context)
              .copyWith(
                color: p.Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

const _editGlyph = Glyph([
  GlyphBox(4, 4, 20, 20, 3),
  GlyphPolyline([
    GlyphVertex(8, 16),
    GlyphVertex(16, 8),
  ], role: GlyphRole.detail),
]);
const _deleteGlyph = Glyph([
  GlyphBox(6, 7, 18, 21, 2),
  GlyphPolyline([
    GlyphVertex(4, 4),
    GlyphVertex(20, 4),
  ], role: GlyphRole.detail),
  GlyphPolyline([
    GlyphVertex(9, 4),
    GlyphVertex(9, 2.5),
    GlyphVertex(15, 2.5),
    GlyphVertex(15, 4),
  ], role: GlyphRole.detail),
]);
