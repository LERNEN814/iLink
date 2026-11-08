import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:luci_mobile/ilink/ilink_models.dart';
import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/models/interface.dart';

class ILinkApiException implements Exception {
  const ILinkApiException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  bool get isAuthentication => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

class ILinkGatewayClient {
  static const _statusPath = '/v1/status';
  static const _clientsPath = '/v1/clients';
  static const _networkPath = '/v1/network';

  static String? validateBaseUrl(String value, {required bool remote}) {
    final input = value.trim();
    if (input.isEmpty) return remote ? '请填写 DDNSTO 地址' : null;
    final uri = Uri.tryParse(input);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return '请输入不带路径的有效 HTTPS 地址';
    }
    return null;
  }

  static String normalizeFingerprint(String value) =>
      value.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();

  static String? validateConfiguration(ILinkProfile profile) {
    final remoteError = validateBaseUrl(profile.remoteUrl, remote: true);
    if (remoteError != null) return remoteError;
    final lanError = validateBaseUrl(profile.lanUrl, remote: false);
    if (lanError != null) return '局域网地址：$lanError';
    if (!RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(profile.token.trim())) {
      return '设备凭据应为 64 位十六进制 token';
    }
    if (profile.lanUrl.isNotEmpty) {
      final fingerprint = normalizeFingerprint(profile.certificateSha256);
      if (!RegExp(r'^[0-9A-F]{64}$').hasMatch(fingerprint)) {
        return '使用局域网 HTTPS 时需要 64 位证书 SHA-256 指纹';
      }
    }
    return null;
  }

  Dio _dio(String baseUrl, {String fingerprint = ''}) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 7),
        receiveTimeout: const Duration(seconds: 12),
        sendTimeout: const Duration(seconds: 7),
        responseType: ResponseType.json,
        followRedirects: false,
        validateStatus: (_) => true,
      ),
    );
    final expected = normalizeFingerprint(fingerprint);
    if (expected.isNotEmpty) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.badCertificateCallback = (cert, host, port) {
            final now = DateTime.now();
            final actual = sha256.convert(cert.der).toString().toUpperCase();
            return expected == actual &&
                now.isAfter(cert.startValidity) &&
                now.isBefore(cert.endValidity);
          };
          return client;
        },
      );
    }
    return dio;
  }

  Future<ILinkData> load(ILinkProfile profile) async {
    final validation = validateConfiguration(profile);
    if (validation != null) throw ILinkApiException(validation);
    final endpoints = <({String url, String transport})>[
      if (profile.lanUrl.trim().isNotEmpty)
        (url: profile.lanUrl.trim(), transport: 'LAN'),
      (url: profile.remoteUrl.trim(), transport: 'DDNSTO'),
    ];
    Object? lastError;
    for (final endpoint in endpoints) {
      try {
        return await _loadAt(profile, endpoint.url, endpoint.transport);
      } catch (error) {
        lastError = error;
        if (error is ILinkApiException && error.isAuthentication) rethrow;
      }
    }
    if (lastError is ILinkApiException) throw lastError;
    throw const ILinkApiException('无法连接网关，请检查 DDNSTO、地址和证书指纹');
  }

  Future<ILinkData> _loadAt(
    ILinkProfile profile,
    String baseUrl,
    String transport,
  ) async {
    final dio = _dio(
      baseUrl,
      fingerprint: transport == 'LAN' ? profile.certificateSha256 : '',
    );
    try {
      final responses = await Future.wait([
        _get(dio, _statusPath, profile.token),
        _get(dio, _clientsPath, profile.token),
        _get(dio, _networkPath, profile.token),
      ]);
      final status = responses[0];
      final clientRows = responses[1]['clients'] as List? ?? const [];
      final interfaceRows = responses[2]['interfaces'] as List? ?? const [];
      final wirelessRows = responses[2]['wireless'] as List? ?? const [];
      return ILinkData(
        status: status,
        clients: clientRows
            .whereType<Map>()
            .map((row) => Client.fromLease(Map<String, dynamic>.from(row)))
            .toList(),
        interfaces: interfaceRows
            .whereType<Map>()
            .map(
              (row) =>
                  NetworkInterface.fromJson(Map<String, dynamic>.from(row)),
            )
            .toList(),
        wireless: wirelessRows
            .whereType<Map>()
            .map(
              (row) => WirelessNetwork.fromJson(Map<String, dynamic>.from(row)),
            )
            .toList(),
        transport: transport,
        fetchedAt: DateTime.now(),
      );
    } on DioException catch (error) {
      if (error.error is HandshakeException ||
          error.error is CertificateException) {
        throw const ILinkApiException('证书校验失败，请核对 LAN 证书 SHA-256 指纹');
      }
      throw ILinkApiException(_dioMessage(error));
    } finally {
      dio.close();
    }
  }

  Future<Map<String, dynamic>> _get(Dio dio, String path, String token) async {
    final response = await dio.get<dynamic>(
      path,
      options: Options(headers: {'Authorization': 'Bearer ${token.trim()}'}),
    );
    final statusCode = response.statusCode ?? 0;
    final body = response.data;
    final map = body is Map<String, dynamic>
        ? body
        : body is String
        ? jsonDecode(body) as Map<String, dynamic>
        : <String, dynamic>{};
    if (statusCode == 401 || statusCode == 403) {
      throw ILinkApiException('设备凭据无效或已被撤销', statusCode);
    }
    if (statusCode == 429) {
      throw const ILinkApiException('请求过于频繁，请稍后重试', 429);
    }
    if (statusCode != 200) {
      throw ILinkApiException('网关返回错误（$statusCode）', statusCode);
    }
    if (map['apiVersion'] != 1 || map['data'] is! Map<String, dynamic>) {
      throw const ILinkApiException('网关协议不兼容，请升级路由器端组件');
    }
    return Map<String, dynamic>.from(map['data'] as Map);
  }

  String _dioMessage(DioException error) {
    final code = error.response?.statusCode;
    if (code != null) return '网关连接失败（HTTP $code）';
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout => '连接网关超时',
      _ => '无法连接网关，请检查网络与 DDNSTO 状态',
    };
  }
}
