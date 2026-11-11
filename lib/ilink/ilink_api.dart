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

  /// Runs [action] against the LAN endpoint, then the remote one, handing it
  /// the endpoint's Dio and its base URL so callers can build absolute links.
  Future<T> _perEndpoint<T>(
    ILinkProfile profile,
    Future<T> Function(Dio dio, String baseUrl) action, {
    required String failure,
  }) async {
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
        final result = await action(dio, endpoint.url);
        _lastTransport = endpoint.transport;
        return result;
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
    if (lastError is ILinkApiException) throw lastError;
    throw ILinkApiException(failure);
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

  /// A play URL for the built-in mpv player.
  ///
  /// LAN playback goes to the dedicated streamer on :8444, which answers HTTP
  /// Range requests, so seeking works. Remote playback falls back to the
  /// gateway CGI route, which cannot seek (uhttpd drops the Range header).
  /// The ticket keeps the long-lived device token out of the player.
  Future<({String url, bool verifyTls})> videoStreamUrl(String path) async {
    final profile = _profile;
    if (profile == null) throw const ILinkApiException('尚未配置连接');
    return _perEndpoint(profile, (dio, baseUrl) async {
      final response = await dio.request<Map<String, dynamic>>(
        '/v1/files/stream-ticket',
        data: {'path': path},
        options: Options(method: 'POST'),
      );
      final ticket =
          ((response.data ?? const {})['data'] as Map?)?['ticket']
              ?.toString() ??
          '';
      if (ticket.isEmpty) throw const ILinkApiException('无法创建流媒体凭据');
      final base = Uri.parse(baseUrl);
      final lan = RegExp(r'^[\d.]+$').hasMatch(base.host);
      final prefix = base.path.endsWith('/')
          ? base.path.substring(0, base.path.length - 1)
          : base.path;
      final target = lan
          // The LAN streamer terminates TLS on 8444 and forwards to the
          // Range-aware process; the CGI route is the remote fallback.
          ? base.replace(port: 8444, path: '/s')
          : base.replace(path: '$prefix/v1/files/stream');
      return (
        url: target.replace(queryParameters: {'ticket': ticket}).toString(),
        verifyTls: !lan,
      );
    }, failure: '无法创建流媒体凭据');
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
    await _perEndpoint<void>(profile, (dio, _) async {
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
      final total =
          int.tryParse(
            response.headers.value(HttpHeaders.contentLengthHeader) ?? '',
          ) ??
          0;
      final sink = File(savePath).openWrite();
      var received = 0;
      try {
        await for (final chunk in response.data!.stream) {
          received += chunk.length;
          sink.add(chunk);
          if (onProgress != null && total > 0) onProgress(received, total);
        }
      } finally {
        await sink.close();
      }
    }, failure: '下载失败');
  }

  /// Uploads a file as a raw body, so size is limited by disk, not by JSON
  /// buffering. Goes straight to the dedicated CGI entry.
  Future<Map<String, dynamic>> uploadFile(
    String path,
    String name,
    String filePath, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final profile = _profile;
    if (profile == null) throw const ILinkApiException('尚未配置连接');
    final total = File(filePath).lengthSync();
    return _perEndpoint(profile, (dio, _) async {
      final response = await dio.post<Map<String, dynamic>>(
        '/v1/files/upload-raw',
        queryParameters: {'path': path, 'name': name},
        data: File(filePath).openRead().map((chunk) => chunk),
        options: Options(
          headers: {HttpHeaders.contentLengthHeader: total},
          receiveTimeout: const Duration(minutes: 30),
        ),
        onSendProgress: onProgress,
      );
      final code = response.statusCode ?? 0;
      if (code == 401 || code == 403) {
        throw ILinkApiException('设备凭据无效或已被撤销', code);
      }
      if (code != 200) throw ILinkApiException('上传失败（HTTP $code）', code);
      final payload = response.data ?? const {};
      final data = payload['data'];
      return data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
    }, failure: '上传失败');
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
