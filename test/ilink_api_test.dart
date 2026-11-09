import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/ilink/ilink_api.dart';
import 'package:luci_mobile/ilink/ilink_models.dart';

void main() {
  const token =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  ILinkProfile profile({String lan = '', String fingerprint = ''}) =>
      ILinkProfile(
        remoteUrl: 'https://home.ddnsto.com',
        token: token,
        lanUrl: lan,
        certificateSha256: fingerprint,
      );

  group('iLink gateway endpoint validation', () {
    test('accepts HTTPS host URLs and normalizes fingerprints', () {
      expect(ILinkGatewayClient.validateConfiguration(profile()), isNull);
      expect(
        ILinkGatewayClient.normalizeFingerprint('21:e2:3f:9a'),
        '21E23F9A',
      );
    });

    test('rejects paths, credentials, HTTP and arbitrary RPC paths', () {
      for (final value in [
        'http://home.ddnsto.com',
        'https://user:password@home.ddnsto.com',
        'https://home.ddnsto.com/ubus',
        'https://home.ddnsto.com/v1/status?x=1',
        'not a url',
      ]) {
        expect(
          ILinkGatewayClient.validateBaseUrl(value, remote: true),
          isNotNull,
          reason: value,
        );
      }
    });

    test('requires an independent token, not a router password', () {
      expect(
        ILinkGatewayClient.validateConfiguration(
          ILinkProfile(
            remoteUrl: 'https://home.ddnsto.com',
            token: 'root-password',
          ),
        ),
        contains('设备凭据'),
      );
    });

    test('requires certificate pinning for LAN HTTPS', () {
      final fingerprint = List.filled(64, 'A').join();
      expect(
        ILinkGatewayClient.validateConfiguration(
          profile(lan: 'https://192.168.100.1:8443'),
        ),
        contains('指纹'),
      );
      expect(
        ILinkGatewayClient.validateConfiguration(
          profile(lan: 'https://192.168.100.1:8443', fingerprint: fingerprint),
        ),
        isNull,
      );
    });
  });
}
