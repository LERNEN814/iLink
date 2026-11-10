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
    this.connectionTotal = 0,
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

  /// Live connections reported by the kernel; the list loads on demand.
  final int connectionTotal;
  final int upload;
  final int download;
  final int uploadTotal;
  final int downloadTotal;

  String get configName => config.split('/').last;

  factory OpenClashData.fromJson(Map<String, dynamic> json) {
    // The gateway reports the live count in /status and the rows only in
    // /connections, so accept either shape here.
    final rawConnections = json['connections'];
    final rows = rawConnections is List ? rawConnections : const [];
    return OpenClashData(
      running: json['running'] == true,
      version: json['version']?.toString() ?? '',
      mode: json['mode']?.toString() ?? 'rule',
      config: json['config']?.toString() ?? '',
      mixedPort: (json['mixedPort'] as num?)?.toInt() ?? 0,
      connectionTotal: (rawConnections is num
          ? rawConnections.toInt()
          : rows.length),
      groups: (json['groups'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => ProxyGroup.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      connections: rows
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
}

class ServiceState {
  const ServiceState({
    required this.id,
    required this.label,
    required this.running,
  });

  final String id;
  final String label;
  final bool running;

  factory ServiceState.fromJson(Map<String, dynamic> json) => ServiceState(
    id: json['id']?.toString() ?? '',
    label: json['label']?.toString() ?? '',
    running: json['running'] == true,
  );
}

class DownloadJob {
  const DownloadJob({
    required this.id,
    required this.name,
    required this.kind,
    required this.progress,
    required this.state,
    required this.detail,
  });

  final String id;
  final String name;
  final String kind;
  final double progress;
  final String state;
  final String detail;

  factory DownloadJob.fromTorrent(Map<String, dynamic> json) => DownloadJob(
    id: json['hash']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    kind: 'torrent',
    progress: (json['progress'] as num?)?.toDouble() ?? 0,
    state: json['state']?.toString() ?? '',
    detail: json['speed'] is num ? '${json['speed']} B/s' : '',
  );

  factory DownloadJob.fromVideo(Map<String, dynamic> json) {
    final tail = (json['tail'] as List? ?? const []).join(' ');
    return DownloadJob(
      id: json['id']?.toString() ?? '',
      name: json['url']?.toString() ?? '',
      kind: 'video',
      progress: (double.tryParse('${json['progress'] ?? ''}') ?? 0) / 100,
      state: json['status']?.toString() ?? '',
      detail: tail.length > 160 ? tail.substring(tail.length - 160) : tail,
    );
  }
}

class ConfigEntry {
  const ConfigEntry({
    required this.name,
    required this.active,
    required this.size,
    this.remaining,
    this.expire,
  });

  final String name;
  final bool active;
  final int size;
  final String? remaining;
  final String? expire;

  factory ConfigEntry.fromJson(Map<String, dynamic> json) => ConfigEntry(
    name: json['name']?.toString() ?? '',
    active: json['active'] == true,
    size: (json['size'] as num?)?.toInt() ?? 0,
    remaining: json['remaining']?.toString(),
    expire: json['expire']?.toString(),
  );
}

class SubscriptionUsage {
  const SubscriptionUsage({
    required this.used,
    required this.total,
    required this.expire,
  });

  final int used;
  final int total;
  final int expire;

  double? get percent => total > 0 ? (used / total).clamp(0, 1) : null;

  factory SubscriptionUsage.fromJson(Map<String, dynamic> json) =>
      SubscriptionUsage(
        used: (json['used'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 0,
        expire: (json['expire'] as num?)?.toInt() ?? 0,
      );
}

class FastNetResult {
  const FastNetResult({required this.summary, required this.logs});

  final Map<String, dynamic> summary;
  final List<String> logs;

  bool get failed => summary['error'] != null;

  factory FastNetResult.fromJson(Map<String, dynamic> json) => FastNetResult(
    summary: Map<String, dynamic>.from(
      json['summary'] as Map? ?? const <String, dynamic>{},
    ),
    logs: (json['logs'] as List? ?? const []).map((item) => '$item').toList(),
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

/// Raw WAN counters; rates are derived from two samples.
class TrafficSample {
  const TrafficSample({
    required this.device,
    required this.rx,
    required this.tx,
    required this.at,
  });

  final String device;
  final double rx;
  final double tx;
  final double at;
}

class UpdateCheck {
  const UpdateCheck({required this.packages, required this.pinned});

  final List<String> packages;

  /// Packages the vendor pins with `hold`: opkg never upgrades them.
  final int pinned;
}

class FirmwareInfo {
  const FirmwareInfo({
    required this.release,
    required this.target,
    required this.kernel,
    required this.available,
  });

  final String release;
  final String target;
  final String kernel;
  final List<String> available;
}

class ExecResult {
  const ExecResult({required this.output, required this.code});

  final String output;
  final int code;
}

/// Exit address and reputation, mirroring FlClash's `IpQuality` model.
class IpQuality {
  const IpQuality({
    required this.ip,
    required this.type,
    required this.country,
    required this.city,
    required this.organization,
    required this.asn,
    required this.isProxy,
    required this.isVpn,
    required this.isTor,
    required this.isAbuser,
    required this.source,
  });

  factory IpQuality.fromJson(Map<String, dynamic> json) => IpQuality(
    ip: json['ip']?.toString() ?? '',
    type: json['type']?.toString() ?? 'residential',
    country: json['country']?.toString() ?? '',
    city: json['city']?.toString() ?? '',
    organization: json['organization']?.toString() ?? '',
    asn: (json['asn'] as num?)?.toInt(),
    isProxy: json['isProxy'] == true,
    isVpn: json['isVpn'] == true,
    isTor: json['isTor'] == true,
    isAbuser: json['isAbuser'] == true,
    source: json['source']?.toString() ?? '',
  );

  final String ip;

  /// residential, mobile, business or hosting.
  final String type;
  final String country;
  final String city;
  final String organization;
  final int? asn;
  final bool isProxy;
  final bool isVpn;
  final bool isTor;
  final bool isAbuser;
  final String source;

  /// FlClash's rule: Tor or abuse reports make an address risky, hosting is
  /// only acceptable, everything else counts as clean.
  String get level => isTor || isAbuser
      ? 'risky'
      : type == 'hosting'
      ? 'normal'
      : 'good';

  String get typeLabel => switch (type) {
    'mobile' => '移动网络',
    'business' => '商业宽带',
    'hosting' => '机房 IP',
    _ => '原生家宽',
  };

  String get levelLabel => switch (level) {
    'risky' => '风险',
    'normal' => '一般',
    _ => '良好',
  };

  /// iLink's own 0-100 reading of the same facts; FlClash only shows a level.
  int get score {
    var value = switch (type) {
      'residential' => 90,
      'mobile' => 85,
      'business' => 75,
      _ => 45,
    };
    if (isProxy) value -= 10;
    if (isVpn) value -= 10;
    if (isTor) value -= 30;
    if (isAbuser) value -= 20;
    return value.clamp(0, 100);
  }

  List<String> get flags => [
    if (isProxy) '代理标记',
    if (isVpn) 'VPN 标记',
    if (isTor) 'Tor 出口',
    if (isAbuser) '滥用记录',
  ];
}
