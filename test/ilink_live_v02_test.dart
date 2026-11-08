import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/ilink/ilink_api.dart';
import 'package:luci_mobile/ilink/ilink_feature_api.dart';
import 'package:luci_mobile/ilink/ilink_models.dart';

const _configPath = String.fromEnvironment('ILINK_LIVE_CONFIG');

// ignore_for_file: avoid_print

void main() {
  test('live gateway serves OpenClash and file endpoints', () async {
    final json = jsonDecode(await File(_configPath).readAsString());
    final client = ILinkGatewayClient()
      ..configure(
        ILinkProfile(
          remoteUrl: json['remoteUrl'] as String? ?? 'https://remote.invalid',
          token: json['token'] as String,
          lanUrl: json['lanUrl'] as String,
          certificateSha256: json['certificateSha256'] as String,
        ),
      );

    final proxy = await OpenClashService(client).load();
    expect(proxy.running, isTrue);
    expect(proxy.groups, isNotEmpty);
    print('groups=${proxy.groups.length} connections=${proxy.connections.length}');

    final files = await FileService(client).list('');
    expect(files, isNotEmpty);
    print('files=${files.length} first=${files.first.name} dir=${files.first.directory}');
  }, skip: _configPath.isEmpty, timeout: const Timeout(Duration(minutes: 2)));
}
