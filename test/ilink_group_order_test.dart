import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/ilink/ilink_feature_models.dart';

ProxyGroup group(String name) =>
    ProxyGroup(name: name, type: 'Selector', now: '', nodes: const []);

void main() {
  test('selector groups lead and GLOBAL trails', () {
    final ordered = orderedProxyGroups([
      group('GLOBAL'),
      group('微软服务'),
      group('自动选择'),
      group('节点选择'),
      group('苹果服务'),
    ]);
    expect(ordered.map((g) => g.name).toList(), [
      '节点选择',
      '自动选择',
      '微软服务',
      '苹果服务',
      'GLOBAL',
    ]);
  });

  test('other groups keep the gateway order', () {
    final ordered = orderedProxyGroups([group('C'), group('A'), group('B')]);
    expect(ordered.map((g) => g.name).toList(), ['C', 'A', 'B']);
  });

  test('a global-only config still works', () {
    expect(orderedProxyGroups([group('GLOBAL')]).single.name, 'GLOBAL');
  });
}
