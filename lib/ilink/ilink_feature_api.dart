import 'dart:convert';
import 'dart:typed_data';

import 'package:luci_mobile/ilink/ilink_api.dart';
import 'package:luci_mobile/ilink/ilink_feature_models.dart';

class OpenClashService {
  OpenClashService(this.client) : _fakeData = null;

  /// In-memory data for widget tests; the gateway is not contacted.
  OpenClashService.fake(OpenClashData data) : client = null, _fakeData = data;

  final ILinkGatewayClient? client;
  final OpenClashData? _fakeData;

  Future<OpenClashData> load() async {
    final fake = _fakeData;
    if (fake != null) return fake;
    final gateway = client!;
    final status = await gateway.json('GET', 'openclash/status');
    final groups = await gateway.json('GET', 'openclash/groups');
    final connections = await gateway.json('GET', 'openclash/connections');
    return OpenClashData.fromJson({
      ...status,
      ...groups,
      'connections': connections['connectionList'] ?? const [],
    });
  }

  Future<List<ProxyConnection>> connectionList() async {
    final fake = _fakeData;
    if (fake != null) return fake.connections;
    final result = await client!.json('GET', 'openclash/connections');
    return (result['connectionList'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => ProxyConnection.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<void> select(String group, String proxy) async {
    if (_fakeData != null) return;
    await client!.json('POST', 'openclash/select', {
      'group': group,
      'proxy': proxy,
    });
  }

  Future<int> testDelay(String proxy) async {
    if (_fakeData != null) return 88;
    final result = await client!.json('POST', 'openclash/test-delay', {
      'proxy': proxy,
    });
    return (result['delay'] as num?)?.toInt() ?? 0;
  }

  Future<({List<String> configs, String current})> configs() async {
    final fake = _fakeData;
    if (fake != null) {
      return (configs: const <String>[], current: fake.configName);
    }
    final result = await client!.json('GET', 'openclash/configs');
    return (
      configs: (result['configs'] as List? ?? const [])
          .map((item) => '$item')
          .toList(),
      current: result['current']?.toString() ?? '',
    );
  }

  Future<void> setMode(String mode) async {
    if (_fakeData != null) return;
    await client!.json('POST', 'openclash/mode', {'mode': mode});
  }

  Future<void> service(String op) async {
    if (_fakeData != null) return;
    await client!.json('POST', 'openclash/service', {'op': op});
  }

  Future<void> switchConfig(String name) async {
    if (_fakeData != null) return;
    await client!.json('POST', 'openclash/switch-config', {'name': name});
  }

  Future<void> close(String id) async {
    if (_fakeData != null) return;
    await client!.json('POST', 'openclash/close', {'id': id});
  }
}

class FileService {
  FileService(this.client) : _fakeEntries = null;

  /// In-memory listing for widget tests; the gateway is not contacted.
  FileService.fake(List<FileEntry> entries)
    : client = null,
      _fakeEntries = entries;

  final ILinkGatewayClient? client;
  final List<FileEntry>? _fakeEntries;

  Future<List<FileEntry>> list(String path) async {
    final fake = _fakeEntries;
    if (fake != null) return fake;
    final result = await client!.json('POST', 'files/list', {'path': path});
    return (result['entries'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => FileEntry.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> mkdir(String path, String name) async {
    if (_fakeEntries != null) return;
    await client!.json('POST', 'files/mkdir', {'path': path, 'name': name});
  }

  Future<void> rename(String path, String name) async {
    if (_fakeEntries != null) return;
    await client!.json('POST', 'files/rename', {'path': path, 'name': name});
  }

  Future<void> remove(String path) async {
    if (_fakeEntries != null) return;
    await client!.json('POST', 'files/remove', {'path': path});
  }

  Future<void> copy(String path, String destination, {String? name}) async {
    if (_fakeEntries != null) return;
    await client!.json('POST', 'files/copy', {
      'path': path,
      'destination': destination,
      // ignore: use_null_aware_elements
      if (name != null) 'name': name,
    });
  }

  Future<void> move(String path, String destination, {String? name}) async {
    if (_fakeEntries != null) return;
    await client!.json('POST', 'files/move', {
      'path': path,
      'destination': destination,
      // ignore: use_null_aware_elements
      if (name != null) 'name': name,
    });
  }

  Future<int> upload(
    String path,
    String name,
    String base64, {
    bool overwrite = false,
  }) async {
    if (_fakeEntries != null) return 0;
    final result = await client!.json('POST', 'files/upload', {
      'path': path,
      'name': name,
      'base64': base64,
      if (overwrite) 'overwrite': true,
    });
    return (result['size'] as num?)?.toInt() ?? 0;
  }

  Future<FilePreview> preview(String path) async {
    if (_fakeEntries != null) {
      return const FilePreview(kind: 'text', content: 'preview');
    }
    final result = await client!.json('POST', 'files/preview', {'path': path});
    return FilePreview.fromJson(result);
  }

  Future<Uint8List> download(String path) async {
    if (_fakeEntries != null) return Uint8List(0);
    final result = await client!.json('POST', 'files/download', {'path': path});
    return base64Decode(result['base64'] as String);
  }
}
