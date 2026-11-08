import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/ilink/ilink_api.dart';
import 'package:luci_mobile/ilink/ilink_models.dart';

const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _fingerprint =
    '59DD30186C0F4E97DEE91E0D745A9654DA8BCABEB641DE1B9E55F526C99D5BAD';

void main() {
  late HttpServer server;
  late String baseUrl;

  setUpAll(() async {
    final context = SecurityContext()
      ..useCertificateChain('test/fixtures/test_cert.pem')
      ..usePrivateKey('test/fixtures/test_key.pem');
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    baseUrl = 'https://localhost:${server.port}';
    server.listen((request) {
      final response = request.response;
      response.headers.contentType = ContentType.json;
      if (request.headers.value('authorization') != 'Bearer $_token') {
        response.statusCode = 401;
        response.write(jsonEncode({'error': 'unauthorized'}));
      } else {
        final data = switch (request.uri.path) {
          '/v1/status' => {
            'hostname': 'iStoreOS',
            'model': 'NanoPi R3S',
            'release': 'iStoreOS test',
            'kernel': '6.6',
            'uptime': 120,
            'load': [0.1, 0.2, 0.3],
            'memory': {'total': 1000, 'available': 250},
          },
          '/v1/clients' => {
            'clients': [
              {
                'macaddr': '00:11:22:33:44:55',
                'ipaddr': '192.168.100.2',
                'hostname': 'phone',
              },
            ],
          },
          '/v1/network' => {
            'interfaces': [
              {
                'interface': 'lan',
                'up': true,
                'proto': 'static',
                'device': 'br-lan',
                'ipv4-address': [
                  {'address': '192.168.100.1', 'mask': 24},
                ],
              },
            ],
            'wireless': [
              {
                'radio': 'radio0',
                'ssid': 'iLink-test',
                'mode': 'ap',
                'channel': 36,
                'band': '5g',
                'up': true,
                'encryption': 'psk2',
              },
            ],
          },
          _ => null,
        };
        if (data == null) {
          response.statusCode = 404;
          response.write(jsonEncode({'error': 'not_found'}));
        } else {
          response.write(jsonEncode({'apiVersion': 1, 'data': data}));
        }
      }
      response.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  ILinkProfile profile({String token = _token, String? fingerprint}) =>
      ILinkProfile(
        remoteUrl: 'https://remote.invalid',
        token: token,
        lanUrl: baseUrl,
        certificateSha256: fingerprint ?? _fingerprint,
      );

  test('pinned HTTPS gateway loads all three read-only endpoints', () async {
    final data = await ILinkGatewayClient().load(profile());
    expect(data.transport, 'LAN');
    expect(data.hostname, 'iStoreOS');
    expect(data.memoryUsage, 0.75);
    expect(data.clients.single.hostname, 'phone');
    expect(data.interfaces.single.ipAddress, '192.168.100.1');
    expect(data.wireless.single.ssid, 'iLink-test');
  });

  test('wrong certificate fingerprint is rejected', () async {
    await expectLater(
      ILinkGatewayClient().load(profile(fingerprint: 'A' * 64)),
      throwsA(isA<ILinkApiException>()),
    );
  });

  test('invalid device token never falls back to another endpoint', () async {
    await expectLater(
      ILinkGatewayClient().load(profile(token: 'b' * 64)),
      throwsA(
        isA<ILinkApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.isAuthentication, 'isAuthentication', true),
      ),
    );
  });
}
