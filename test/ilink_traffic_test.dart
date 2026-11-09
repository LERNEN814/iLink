import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/ilink/ilink_feature_models.dart';

/// The card derives rates from two counter samples; a router reboot or a
/// counter reset must not plot a negative or absurd spike.
(double, double) rate(TrafficSample previous, TrafficSample next) {
  final seconds = next.at - previous.at;
  if (seconds <= 0) return (0, 0);
  final rx = next.rx >= previous.rx ? (next.rx - previous.rx) / seconds : 0.0;
  final tx = next.tx >= previous.tx ? (next.tx - previous.tx) / seconds : 0.0;
  return (rx, tx);
}

void main() {
  test('computes per-second rates from two samples', () {
    final first = TrafficSample(device: 'eth0', rx: 1000, tx: 500, at: 10);
    final second = TrafficSample(device: 'eth0', rx: 3048, tx: 1524, at: 12);
    final (rx, tx) = rate(first, second);
    expect(rx, closeTo(1024, 0.001));
    expect(tx, closeTo(512, 0.001));
  });

  test('a counter reset reports zero instead of a negative rate', () {
    final first = TrafficSample(device: 'eth0', rx: 900000, tx: 800000, at: 10);
    final second = TrafficSample(device: 'eth0', rx: 1200, tx: 900, at: 11);
    expect(rate(first, second), (0.0, 0.0));
  });

  test('a stale timestamp is ignored', () {
    final first = TrafficSample(device: 'eth0', rx: 10, tx: 10, at: 20);
    final second = TrafficSample(device: 'eth0', rx: 90, tx: 90, at: 20);
    expect(rate(first, second), (0.0, 0.0));
  });
}
