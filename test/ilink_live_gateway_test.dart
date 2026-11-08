import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/ilink/ilink_api.dart';
import 'package:luci_mobile/ilink/ilink_models.dart';

const _configPath = String.fromEnvironment('ILINK_LIVE_CONFIG');

void main() {
  test(
    'live iStoreOS gateway supports pinned HTTPS and rejects a bad token',
    () async {
      final json = jsonDecode(await File(_configPath).readAsString());
      final profile = ILinkProfile(
        remoteUrl: 'https://remote.invalid',
        token: json['token'] as String,
        lanUrl: json['lanUrl'] as String,
        certificateSha256: json['certificateSha256'] as String,
      );
      final data = await ILinkGatewayClient().load(profile);
      expect(data.transport, 'LAN');
      expect(data.model, contains('NanoPi R3S'));
      expect(data.release, contains('iStoreOS'));
      expect(data.interfaces, isNotEmpty);

      await expectLater(
        ILinkGatewayClient().load(
          ILinkProfile(
            remoteUrl: profile.remoteUrl,
            token: 'b' * 64,
            lanUrl: profile.lanUrl,
            certificateSha256: profile.certificateSha256,
          ),
        ),
        throwsA(
          isA<ILinkApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
    },
    skip: _configPath.isEmpty,
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
