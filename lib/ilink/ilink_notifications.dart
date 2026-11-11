import 'package:flutter/services.dart';

/// Progress and completion notices for long transfers. Android-only; on any
/// other platform the channel is missing and every call is a no-op.
class TransferNotifier {
  const TransferNotifier();

  static const _channel = MethodChannel('ilink/notify');

  Future<int?> progress({
    required int id,
    required String title,
    required String text,
    required double fraction,
  }) async {
    try {
      return await _channel.invokeMethod<int>('progress', {
        'id': id,
        'title': title,
        'text': text,
        'progress': (fraction.clamp(0.0, 1.0) * 100).round(),
        'max': 100,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> done({
    required int id,
    required String title,
    required String text,
    bool failed = false,
  }) async {
    try {
      await _channel.invokeMethod<void>('done', {
        'id': id,
        'title': title,
        'text': text,
        'failed': failed,
      });
    } on MissingPluginException {
      // Desktop and tests have no notification service.
    } on PlatformException {
      // A denied notification permission must never break the transfer.
    }
  }

  Future<void> cancel(int id) async {
    try {
      await _channel.invokeMethod<void>('cancel', {'id': id});
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    }
  }
}

/// Stable notification id per transfer subject.
int notificationIdFor(String key) => 4100 + (key.hashCode & 0x3FF);
