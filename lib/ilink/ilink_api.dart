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

  ILinkProfile? _profile;
  String _lastTransport = 'DDNSTO';

  void configure(ILinkProfile profile) => _profile = profile;

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
    final hasLan = profile.lanUrl.trim().isNotEmpty;
    final hasRemote = profile.remoteUrl.trim().isNotEmpty;
    if (!hasLan && !hasRemote) return '请至少填写 DDNSTO 地址或局域网地址';
    final lanError = validateBaseUrl(profile.lanUrl, remote: false);
    if (lanError != null) return '局域网地址：$lanError';
    final remoteError = validateBaseUrl(profile.remoteUrl, remote: false);
    if (remoteError != null) return remoteError;
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

  Dio _dio(String baseUrl, String token, {String fingerprint = ''}) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 7),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 7),
        responseType: ResponseType.json,
        followRedirects: false,
        headers: {'Authorization': 'Bearer ${token.trim()}'},
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

  List<({String url, String transport})> _endpoints(ILinkProfile profile) => [
    if (profile.lanUrl.trim().isNotEmpty)
      (url: profile.lanUrl.trim(), transport: 'LAN'),
    (url: profile.remoteUrl.trim(), transport: 'DDNSTO'),
  ];

  Future<T> _request<T>(
    ILinkProfile profile,
    Future<T> Function(Dio) action,
  ) async {
    final validation = validateConfiguration(profile);
    if (validation != null) throw ILinkApiException(validation);
    Object? lastError;
    for (final endpoint in _endpoints(profile)) {
      final dio = _dio(
        endpoint.url,
        profile.token,
        fingerprint: endpoint.transport == 'LAN'
            ? profile.certificateSha256
            : '',
      );
      try {
        final result = await action(dio);
        _lastTransport = endpoint.transport;
        return result;
      } on DioException catch (error) {
        final code = error.response?.statusCode;
        if (code == 401 || code == 403) {
          throw ILinkApiException('设备凭据无效或已被撤销', code);
        }
        lastError = ILinkApiException(_dioMessage(error));
        if (endpoint == _endpoints(profile).last) {
          throw lastError;
        }
        await Future<void>.delayed(Duration.zero);
      } on HandshakeException catch (error) {
        lastError = error;
        if (endpoint == _endpoints(profile).last) {
          throw const ILinkApiException('证书校验失败，请核对 LAN 证书 SHA-256 指纹');
        }
      } catch (error) {
        lastError = error;
        if (error is ILinkApiException && error.isAuthentication) rethrow;
      } finally {
        dio.close();
      }
    }
    if (lastError is ILinkApiException) throw lastError;
    throw const ILinkApiException('无法连接网关，请检查 DDNSTO、地址和证书指纹');
  }

  Future<Map<String, dynamic>> _parse(Response<dynamic> response) async {
    final code = response.statusCode ?? 0;
    final body = response.data;
    final map = body is Map<String, dynamic>
        ? body
        : body is String
        ? jsonDecode(body) as Map<String, dynamic>
        : <String, dynamic>{};
    if (code == 401 || code == 403) {
      throw ILinkApiException('设备凭据无效或已被撤销', code);
    }
    if (code == 429) throw const ILinkApiException('请求过于频繁，请稍后重试', 429);
    if (code != 200) throw ILinkApiException('网关返回错误（$code）', code);
    if (map['apiVersion'] != 1 || map['data'] is! Map<String, dynamic>) {
      throw const ILinkApiException('网关协议不兼容，请升级路由器端组件');
    }
    return Map<String, dynamic>.from(map['data'] as Map);
  }

  Future<Map<String, dynamic>> _get(Dio dio, String path) async =>
      _parse(await dio.get<dynamic>(path));

  Future<Map<String, dynamic>> json(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    var route = path.startsWith('v1/') ? path : 'v1/$path';
    if (route.startsWith('/')) route = route.substring(1);
    if (route.contains('..') ||
        route.contains(RegExp(r'[?#\\]')) ||
        !RegExp(r'^v1/[a-z0-9/-]+$').hasMatch(route)) {
      throw const ILinkApiException('无效网关路径');
    }
    final profile = _profile;
    if (profile == null) throw const ILinkApiException('尚未配置连接');
    return _request(
      profile,
      (dio) async => _parse(
        await dio.request<dynamic>(
          '/$route',
          data: body,
          options: Options(
            method: method,
            receiveTimeout: route == 'v1/files/download'
                ? const Duration(minutes: 5)
                : route.startsWith('v1/fastnet/')
                ? const Duration(minutes: 3)
                : const Duration(seconds: 15),
          ),
        ),
      ),
    );
  }

  /// Issues a short-lived, path-locked stream ticket for the media player.
  Future<String> streamTicket(String path) async {
    final result = await json('POST', 'files/stream-ticket', {'path': path});
    return result['ticket']?.toString() ?? '';
  }

  /// A play URL for the built-in mpv player. The ticket keeps the long-lived
  /// device token out of the player; LAN hosts (self-signed certificates) ask
  /// mpv to skip TLS verification, remote domains keep it on.
  Future<({String url, bool verifyTls})> videoStreamUrl(String path) async {
    final profile = _profile;
    if (profile == null) throw const ILinkApiException('尚未配置连接');
    Object? lastError;
    for (final endpoint in _endpoints(profile)) {
      final dio = _dio(
        endpoint.url,
        profile.token,
        fingerprint: endpoint.transport == 'LAN'
            ? profile.certificateSha256
            : '',
      );
      try {
        final response = await dio.request<Map<String, dynamic>>(
          '/v1/files/stream-ticket',
          data: {'path': path},
          options: Options(method: 'POST'),
        );
        final ticket =
            ((response.data ?? const {})['data'] as Map?)?['ticket']
                ?.toString() ??
            '';
        if (ticket.isEmpty) {
          throw const ILinkApiException('无法创建流媒体凭据');
        }
        final base = Uri.parse(endpoint.url);
        final uri = base.replace(
          path:
              '${base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path}/v1/files/stream',
          queryParameters: {'ticket': ticket},
        );
        final host = base.host;
        return (
          url: uri.toString(),
          verifyTls: !RegExp(r'^[\d.]+$').hasMatch(host),
        );
      } on DioException catch (error) {
        lastError = ILinkApiException(_dioMessage(error));
      } finally {
        dio.close();
      }
    }
    throw lastError ?? const ILinkApiException('无法创建流媒体凭据');
  }

  /// Streams a raw gateway file to disk; no size cap because nothing is
  /// buffered whole in memory.
  Future<void> downloadFile(
    String route,
    Map<String, String> query,
    String savePath, {
    void Function(int received, int total)? onProgress,
  }) async {
    final profile = _profile;
    if (profile == null) throw const ILinkApiException('尚未配置连接');
    Object? lastError;
    for (final endpoint in _endpoints(profile)) {
      final dio = _dio(
        endpoint.url,
        profile.token,
        fingerprint: endpoint.transport == 'LAN'
            ? profile.certificateSha256
            : '',
      );
      try {
        final response = await dio.get<ResponseBody>(
          route,
          queryParameters: query,
          options: Options(
            responseType: ResponseType.stream,
            receiveTimeout: const Duration(minutes: 30),
          ),
        );
        final code = response.statusCode ?? 0;
        if (code != 200 && code != 206) {
          throw ILinkApiException('下载失败（HTTP $code）', code);
        }
        final body = response.data!;
        final total =
            int.tryParse(
              response.headers.value(HttpHeaders.contentLengthHeader) ?? '',
            ) ??
            0;
        final sink = File(savePath).openWrite();
        var received = 0;
        try {
          await for (final chunk in body.stream) {
            received += chunk.length;
            sink.add(chunk);
            if (onProgress != null && total > 0) onProgress(received, total);
          }
        } finally {
          await sink.close();
        }
        return;
      } on DioException catch (error) {
        final code = error.response?.statusCode;
        if (code == 401 || code == 403) {
          throw ILinkApiException('设备凭据无效或已被撤销', code);
        }
        lastError = ILinkApiException(_dioMessage(error));
      } finally {
        dio.close();
      }
    }
    throw lastError ?? const ILinkApiException('下载失败');
  }

  Future<ILinkData> load(ILinkProfile profile) async {
    _profile = profile;
    final responses = await _request(
      profile,
      (dio) => Future.wait([
        _get(dio, _statusPath),
        _get(dio, _clientsPath),
        _get(dio, _networkPath),
      ]),
    );
    return ILinkData(
      status: responses[0],
      clients: (responses[1]['clients'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Client.fromLease(Map<String, dynamic>.from(row)))
          .toList(),
      interfaces: (responses[2]['interfaces'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) => NetworkInterface.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(),
      wireless: (responses[2]['wireless'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) => WirelessNetwork.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(),
      transport: _lastTransport,
      fetchedAt: DateTime.now(),
    );
  }

  String _dioMessage(DioException error) {
    final code = error.response?.statusCode;
    if (code != null) return '网关连接失败（HTTP $code）';
    if (error.error is HandshakeException ||
        error.error is CertificateException) {
      return '证书校验失败，请核对 LAN 证书 SHA-256 指纹';
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout => '连接网关超时',
      _ => '无法连接网关，请检查网络与 DDNSTO 状态',
    };
  }
}
