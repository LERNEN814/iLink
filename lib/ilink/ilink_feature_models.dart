class ProxyNode {
  const ProxyNode({
    required this.name,
    required this.type,
    required this.alive,
    required this.delay,
  });

  final String name;
  final String type;
  final bool alive;
  final int delay;

  factory ProxyNode.fromJson(Map<String, dynamic> json) => ProxyNode(
    name: json['name']?.toString() ?? '',
    type: json['type']?.toString() ?? '',
    alive: json['alive'] == true,
    delay: (json['delay'] as num?)?.toInt() ?? 0,
  );
}

class ProxyGroup {
  const ProxyGroup({
    required this.name,
    required this.type,
    required this.now,
    required this.nodes,
  });

  final String name;
  final String type;
  final String now;
  final List<ProxyNode> nodes;

  factory ProxyGroup.fromJson(Map<String, dynamic> json) => ProxyGroup(
    name: json['name']?.toString() ?? '',
    type: json['type']?.toString() ?? '',
    now: json['now']?.toString() ?? '',
    nodes: (json['nodes'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => ProxyNode.fromJson(Map<String, dynamic>.from(item)))
        .toList(),
  );
}

class ProxyConnection {
  const ProxyConnection({
    required this.id,
    required this.host,
    required this.chain,
    required this.rule,
    required this.upload,
    required this.download,
  });

  final String id;
  final String host;
  final List<String> chain;
  final String rule;
  final int upload;
  final int download;

  factory ProxyConnection.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'] as Map? ?? const {};
    return ProxyConnection(
      id: json['id']?.toString() ?? '',
      host: [
        metadata['host']?.toString() ??
            metadata['destinationIP']?.toString() ??
            '',
        metadata['destinationPort']?.toString() ?? '',
      ].where((item) => item.isNotEmpty).join(':'),
      chain: (json['chains'] as List? ?? const [])
          .map((item) => '$item')
          .toList(),
      rule: '${json['rule'] ?? ''} ${json['rulePayload'] ?? ''}'.trim(),
      upload: (json['upload'] as num?)?.toInt() ?? 0,
      download: (json['download'] as num?)?.toInt() ?? 0,
    );
  }
}

class OpenClashData {
  const OpenClashData({
    required this.running,
    required this.version,
    required this.mode,
    required this.config,
    required this.mixedPort,
    required this.groups,
    required this.connections,
    required this.upload,
    required this.download,
    required this.uploadTotal,
    required this.downloadTotal,
  });

  final bool running;
  final String version;
  final String mode;
  final String config;
  final int mixedPort;
  final List<ProxyGroup> groups;
  final List<ProxyConnection> connections;
  final int upload;
  final int download;
  final int uploadTotal;
  final int downloadTotal;

  String get configName => config.split('/').last;

  factory OpenClashData.fromJson(Map<String, dynamic> json) => OpenClashData(
    running: json['running'] == true,
    version: json['version']?.toString() ?? '',
    mode: json['mode']?.toString() ?? 'rule',
    config: json['config']?.toString() ?? '',
    mixedPort: (json['mixedPort'] as num?)?.toInt() ?? 0,
    groups: (json['groups'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => ProxyGroup.fromJson(Map<String, dynamic>.from(item)))
        .toList(),
    connections: (json['connections'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => ProxyConnection.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(),
    upload: (json['upload'] as num?)?.toInt() ?? 0,
    download: (json['download'] as num?)?.toInt() ?? 0,
    uploadTotal: (json['uploadTotal'] as num?)?.toInt() ?? 0,
    downloadTotal: (json['downloadTotal'] as num?)?.toInt() ?? 0,
  );
}

class FilePreview {
  const FilePreview({required this.kind, this.content, this.base64, this.mime});

  final String kind;
  final String? content;
  final String? base64;
  final String? mime;

  factory FilePreview.fromJson(Map<String, dynamic> json) => FilePreview(
    kind: json['kind']?.toString() ?? 'binary',
    content: json['content']?.toString(),
    base64: json['base64']?.toString(),
    mime: json['mime']?.toString(),
  );
}

class FileEntry {
  const FileEntry({
    required this.name,
    required this.path,
    required this.directory,
    required this.size,
    required this.modified,
  });

  final String name;
  final String path;
  final bool directory;
  final int size;
  final int modified;

  factory FileEntry.fromJson(Map<String, dynamic> json) => FileEntry(
    name: json['name']?.toString() ?? '',
    path: json['path']?.toString() ?? '',
    directory: json['directory'] == true,
    size: (json['size'] as num?)?.toInt() ?? 0,
    modified: (json['modified'] as num?)?.toInt() ?? 0,
  );
}

/// Orders proxy groups for the tab strip: the two everyday selectors first,
/// GLOBAL last, everything else in the gateway's order between them.
List<ProxyGroup> orderedProxyGroups(List<ProxyGroup> groups) {
  int rank(ProxyGroup group) {
    final name = group.name.toUpperCase();
    if (group.name.contains('节点选择')) return 0;
    if (group.name.contains('自动选择')) return 1;
    if (name.contains('GLOBAL')) return 3;
    return 2;
  }

  final indexed = groups.indexed.toList()
    ..sort((a, b) {
      final byRank = rank(a.$2).compareTo(rank(b.$2));
      return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
    });
  return [for (final entry in indexed) entry.$2];
}
