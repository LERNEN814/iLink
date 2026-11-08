import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/ilink/ilink_api.dart';
import 'package:luci_mobile/ilink/ilink_feature_api.dart';
import 'package:luci_mobile/ilink/ilink_models.dart';

const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _fingerprint =
    '59DD30186C0F4E97DEE91E0D745A9654DA8BCABEB641DE1B9E55F526C99D5BAD';

void main() {
  late HttpServer server;
  late String baseUrl;

  setUp(() async {
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
          '/v1/openclash/status' => {
            'running': true,
            'version': 'test-core',
            'mode': 'rule',
            'mixedPort': 7893,
            'config': '/etc/openclash/config/test.yaml',
            'upload': 10,
            'download': 20,
            'uploadTotal': 100,
            'downloadTotal': 200,
            'connections': 1,
          },
          '/v1/openclash/overview' => {
            'running': true,
            'version': 'test-core',
            'mode': 'rule',
            'mixedPort': 7893,
            'config': '/etc/openclash/config/test.yaml',
            'upload': 10,
            'download': 20,
            'uploadTotal': 100,
            'downloadTotal': 200,
            'connections': 1,
            'groups': [
              {
                'name': 'Proxy Select',
                'type': 'Selector',
                'now': 'Node 1',
                'nodes': [
                  {
                    'name': 'Node 1',
                    'type': 'Shadowsocks',
                    'alive': true,
                    'delay': 88,
                  },
                ],
              },
            ],
          },
          '/v1/openclash/groups' => {
            'groups': [
              {
                'name': 'Proxy Select',
                'type': 'Selector',
                'now': 'Node 1',
                'nodes': [
                  {
                    'name': 'Node 1',
                    'type': 'Shadowsocks',
                    'alive': true,
                    'delay': 88,
                  },
                ],
              },
            ],
          },
          '/v1/openclash/connections' => {
            'connectionList': [
              {
                'id': 'abc-123',
                'metadata': {'host': 'example.com', 'destinationPort': '443'},
                'chains': ['Node 1', 'Proxy Select'],
                'rule': 'MATCH',
                'upload': 10,
                'download': 20,
              },
            ],
          },
          '/v1/openclash/select' => {'changed': true},
          '/v1/openclash/test-delay' => {'delay': 88},
          '/v1/openclash/close' => {'closed': true},
          '/v1/files/list' => {
            'path': '',
            'entries': [
              {'name': 'docs', 'path': 'docs', 'directory': true, 'size': 0},
              {
                'name': 'note.txt',
                'path': 'note.txt',
                'directory': false,
                'size': 5,
              },
            ],
          },
          '/v1/alist/list' => {
            'path': '/video',
            'write': true,
            'entries': [
              {
                'name': 'movie.mp4',
                'path': '/video/movie.mp4',
                'directory': false,
                'size': 1024,
              },
            ],
          },
          '/v1/fastnet/quick' => {
            'summary': {
              'pingMs': 33.9,
              'downloadBps': 530256000,
              'natError': 'stun timeout',
            },
            'logs': ['=== 快速体检开始 ===', '下载速度：530.3 Mbps'],
            'stages': [],
          },
          '/v1/files/download' => {
            'name': 'note.txt',
            'size': 5,
            'base64': 'aGVsbG8=',
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

  tearDown(() => server.close(force: true));

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

  test('OpenClash and file services use fixed HTTPS routes', () async {
    final client = ILinkGatewayClient()..configure(profile());
    final proxy = await OpenClashService(client).load();
    expect(proxy.groups.single.nodes.single.delay, 88);
    expect(proxy.connectionTotal, 1);
    final connections = await OpenClashService(client).connectionList();
    expect(connections.single.host, 'example.com:443');
    expect(proxy.configName, 'test.yaml');
    await OpenClashService(client).select('Proxy Select', 'Node 1');
    expect(await OpenClashService(client).testDelay('Node 1'), 88);

    final alist = await AlistService(client).list('/video');
    expect(alist.single.name, 'movie.mp4');
    expect(alist.single.directory, isFalse);

    final fastNet = await FastNetService(client).quick();
    expect(fastNet.summary['pingMs'], 33.9);
    expect(fastNet.summary['natError'], 'stun timeout');
    expect(fastNet.logs.length, 2);
    expect(fastNet.failed, isFalse);

    final files = FileService(client);
    expect((await files.list('')).last.name, 'note.txt');
    expect(String.fromCharCodes(await files.download('note.txt')), 'hello');
  });

  test('invalid device token never falls back to another endpoint', () async {
    await expectLater(
      ILinkGatewayClient().load(profile(token: 'b' * 64)),
      throwsA(
        isA<ILinkApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having(
              (error) => error.isAuthentication,
              'isAuthentication',
              true,
            ),
      ),
    );
  });
}
