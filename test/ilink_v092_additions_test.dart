import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/ilink/ilink_feature_models.dart';
import 'package:luci_mobile/ilink/ilink_notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('notification ids', () {
    test('same subject maps to the same channel id', () {
      expect(
        notificationIdFor('video/a.mp4'),
        notificationIdFor('video/a.mp4'),
      );
    });

    test('different subjects stay inside the reserved window', () {
      final ids = [
        for (final name in ['a.mp4', 'b.mkv', 'c.zip', 'd.bin'])
          notificationIdFor(name),
      ];
      expect(ids.toSet().length, greaterThan(1));
      for (final id in ids) {
        expect(id, greaterThanOrEqualTo(4100));
        expect(id, lessThan(4100 + 1024));
      }
    });
  });

  group('transfer notifier is silent without a platform', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('ilink/notify'), null);
    });

    test('progress and done never throw on an unsupported host', () async {
      const notifier = TransferNotifier();
      await notifier.progress(id: 1, title: 't', text: 'x', fraction: 0.5);
      await notifier.done(id: 1, title: 't', text: 'x');
      await notifier.cancel(1);
    });

    test('a handler that throws does not break the transfer', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('ilink/notify'),
            (call) async => throw PlatformException(code: 'denied_permission'),
          );
      const notifier = TransferNotifier();
      await notifier.done(id: 2, title: 't', text: 'x', failed: true);
    });
  });

  group('exec result', () {
    test('defaults to untruncated', () {
      const result = ExecResult(output: 'ok', code: 0);
      expect(result.truncated, isFalse);
    });
  });

  group('network snapshot rows', () {
    test('gateway timestamps convert to local DateTime', () {
      final modified = DateTime.fromMillisecondsSinceEpoch(1794404826 * 1000);
      expect(modified.isAfter(DateTime(2026)), isTrue);
    });
  });
}
