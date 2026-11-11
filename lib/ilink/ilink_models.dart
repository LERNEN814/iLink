import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/models/interface.dart';

class ILinkProfile {
  const ILinkProfile({
    required this.remoteUrl,
    required this.token,
    this.lanUrl = '',
    this.certificateSha256 = '',
  });

  final String remoteUrl;
  final String token;
  final String lanUrl;
  final String certificateSha256;

  Map<String, dynamic> toJson() => {
    'remoteUrl': remoteUrl,
    'token': token,
    'lanUrl': lanUrl,
    'certificateSha256': certificateSha256,
  };

  factory ILinkProfile.fromJson(Map<String, dynamic> json) => ILinkProfile(
    remoteUrl: json['remoteUrl'] as String? ?? '',
    token: json['token'] as String? ?? '',
    lanUrl: json['lanUrl'] as String? ?? '',
    certificateSha256: json['certificateSha256'] as String? ?? '',
  );
}

class ILinkData {
  const ILinkData({
    required this.status,
    required this.clients,
    required this.interfaces,
    required this.transport,
    required this.fetchedAt,
  });

  final Map<String, dynamic> status;
  final List<Client> clients;
  final List<NetworkInterface> interfaces;
  final String transport;
  final DateTime fetchedAt;

  String get hostname => status['hostname']?.toString() ?? 'iStoreOS';
  String get model => status['model']?.toString() ?? 'OpenWrt';
  String get release => status['release']?.toString() ?? '';
  String get kernel => status['kernel']?.toString() ?? '';
  int get uptime => (status['uptime'] as num?)?.toInt() ?? 0;
  List<double> get load => (status['load'] as List? ?? const [])
      .map((value) => (value as num).toDouble())
      .toList();
  Map<String, dynamic> get memory =>
      status['memory'] as Map<String, dynamic>? ?? const {};

  double get memoryUsage {
    final total = (memory['total'] as num?)?.toDouble() ?? 0;
    final available = (memory['available'] as num?)?.toDouble() ?? 0;
    return total <= 0 ? 0 : ((total - available) / total).clamp(0, 1);
  }

  int get onlineInterfaces => interfaces.where((item) => item.isUp).length;
}

String formatUptime(int seconds) {
  final duration = Duration(seconds: seconds);
  final days = duration.inDays;
  final hours = duration.inHours.remainder(24);
  final minutes = duration.inMinutes.remainder(60);
  if (days > 0) return '$days 天 $hours 小时';
  if (hours > 0) return '$hours 小时 $minutes 分钟';
  return '$minutes 分钟';
}

String formatBytes(num? value) {
  if (value == null) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = value.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(size >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
}
