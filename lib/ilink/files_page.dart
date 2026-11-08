import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:file_picker/file_picker.dart';
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
  late final AlistService _alist;
  int _source = 0; // 0 = router storage, 1 = AList
  String _alistPath = '/';
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
    _alist = AlistService(ref.read(iLinkProvider).client);
    _refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _dir => _source == 0 ? _path : _alistPath;

  static String _parentOf(String path) {
    final index = path.lastIndexOf('/');
    return index <= 0 ? '/' : path.substring(0, index);
  }

  Future<List<FileEntry>> _list(String path) =>
      _source == 0 ? _service.list(path) : _alist.list(path);

  Future<void> _mkdirAt(String dir, String name) =>
      _source == 0 ? _service.mkdir(dir, name) : _alist.mkdir(dir, name);

  Future<void> _renameTo(String path, String name) =>
      _source == 0 ? _service.rename(path, name) : _alist.rename(path, name);

  Future<void> _deleteEntry(FileEntry entry) => _source == 0
      ? _service.remove(entry.path)
      : _alist.remove(_parentOf(entry.path), [entry.name]);

  Future<int> _uploadFile(
    String name,
    String base64, {
    bool overwrite = false,
  }) => _source == 0
      ? _service.upload(_dir, name, base64, overwrite: overwrite)
      : _alist.upload(_dir, name, base64);

  Future<Uint8List> _downloadBytes(FileEntry entry) => _source == 0
      ? _service.download(entry.path)
      : _alist.download(entry.path);

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final entries = await _list(_dir);
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

  Future<void> _preview(FileEntry entry) async {
    setState(() => _busy = true);
    try {
      final preview = await _service.preview(entry.path);
      if (!mounted) return;
      await p.showFloatingDialog<void>(
        context: context,
        child: p.AlertDialog(
          title: entry.name,
          actions: [
            p.TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
          child: switch (preview.kind) {
            'text' => ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: Text(
                  preview.content ?? '',
                  style: p.AppTextStyle.caption1.of(context),
                ),
              ),
            ),
            'image' when preview.base64 != null => ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: Image.memory(
                base64Decode(preview.base64!),
                fit: BoxFit.contain,
              ),
            ),
            _ => Text(
              '此类型暂不支持预览，请下载后查看（${formatBytes(entry.size)}）。',
              style: p.AppTextStyle.footnote.of(context),
            ),
          },
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final picked = await FilePicker.pickFiles();
    final file = picked.isEmpty ? null : picked.first;
    final bytes = file == null ? null : await File(file.path!).readAsBytes();
    if (file == null || bytes == null) return;
    if (bytes.length > 32 * 1024 * 1024) {
      setState(() => _error = 'v0.3 上传上限为 32 MB');
      return;
    }
    setState(() => _busy = true);
    try {
      await _uploadFile(file.name, base64Encode(bytes));
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      final exists = error.toString().contains('exists');
      if (!exists) {
        setState(() => _error = error.toString());
        return;
      }
      final overwrite = await p.showFloatingDialog<bool>(
        context: context,
        child: p.AlertDialog(
          title: '文件已存在',
          destructive: true,
          actions: [
            p.TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            p.TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('覆盖'),
            ),
          ],
          child: Text('${file.name} 已存在，是否覆盖？'),
        ),
      );
      if (overwrite == true) {
        await _uploadFile(file.name, base64Encode(bytes), overwrite: true);
        await _refresh();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _transfer(FileEntry entry, {required bool move}) async {
    final controller = TextEditingController(text: _path);
    final destination = await p.showFloatingDialog<String>(
      context: context,
      child: p.InputDialog(
        title: move ? '移动到目录' : '复制到目录',
        value: controller.text,
        labelText: '目标目录（留空为根目录）',
        validator: (value) {
          final path = value?.trim() ?? '';
          if (path.contains('..') || path.startsWith('/')) return '请输入相对路径';
          return null;
        },
      ),
    );
    controller.dispose();
    if (destination == null || !mounted) return;
    await _run(
      () => move
          ? _service.move(entry.path, destination.trim())
          : _service.copy(entry.path, destination.trim()),
    );
  }

  void _open(FileEntry entry) {
    if (entry.directory) {
      setState(() {
        if (_source == 0) {
          _history.add(_path);
          _path = entry.path;
        } else {
          _alistPath = entry.path;
        }
        _search.clear();
      });
      _refresh();
    } else if (_source == 0) {
      _preview(entry);
    } else {
      _download(entry);
    }
  }

  Future<void> _back() async {
    if (_source == 0) {
      if (_history.isEmpty) return;
      setState(() => _path = _history.last);
      _history.remove(_history.last);
    } else {
      if (_alistPath == '/') return;
      setState(() => _alistPath = _parentOf(_alistPath));
    }
    await _refresh();
  }

  Future<void> _download(FileEntry entry) async {
    if (entry.size > 32 * 1024 * 1024) {
      setState(() => _error = 'v0.2 下载上限为 32 MB；大文件传输任务将在后续版本提供');
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await _downloadBytes(entry);
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
          ? _mkdirAt(_dir, name.trim())
          : _renameTo(entry.path, name.trim()),
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
    if (confirmed == true) await _run(() => _deleteEntry(entry));
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
    final rawMounts = state.data?.status['mounts'];
    final mounts = rawMounts is List ? rawMounts : const <dynamic>[];
    final storage = mounts.whereType<Map>().firstWhere(
      (item) => item['mount'] == '/mnt/data_sdb1',
      orElse: () => const <String, dynamic>{},
    );
    final size = storage['size'] as num?;
    final available = storage['available'] as num?;
    return ILinkPage(
      title: '文件',
      refreshing: _loading,
      onRefresh: _busy ? null : _refresh,
      children: [
        p.SegmentedControl<int>(
          segments: const [(0, '路由器存储'), (1, 'AList')],
          value: _source,
          onChanged: _busy
              ? (_) {}
              : (value) {
                  setState(() {
                    _source = value;
                    _search.clear();
                  });
                  _refresh();
                },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (_dir != '' && _dir != '/')
              p.TextButton(onPressed: _back, child: const Text('‹ 上级')),
            Expanded(
              child: Text(
                _source == 0
                    ? '/mnt/data_sdb1${_path.isEmpty ? '' : '/$_path'}'
                    : _alistPath,
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
        if (_source == 0)
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
                  onPressed: _busy ? null : _upload,
                  child: const Text('上传'),
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
                if (_source == 0 && !entry.directory)
                  p.PopupMenuItem(
                    label: '复制到…',
                    onPressed: () => _transfer(entry, move: false),
                  ),
                if (_source == 0)
                  p.PopupMenuItem(
                    label: '移动到…',
                    onPressed: () => _transfer(entry, move: true),
                  ),
                if (!entry.directory)
                  p.PopupMenuItem(
                    label: '下载',
                    onPressed: () => _download(entry),
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
          _source == 0
              ? '路由器存储：仅限 /mnt/data_sdb1，禁止系统目录、路径穿越与符号链接。长按可重命名、复制、移动、下载或删除。'
              : 'AList：使用路由器上保存的受限账号，仅能访问该账号被授权的目录。长按可重命名、下载或删除。',
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
