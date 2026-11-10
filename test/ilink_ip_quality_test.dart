import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/ilink/ilink_feature_models.dart';

IpQuality build({
  String type = 'residential',
  bool proxy = false,
  bool vpn = false,
  bool tor = false,
  bool abuser = false,
}) => IpQuality(
  ip: '64.81.31.196',
  type: type,
  country: 'United States',
  city: 'Los Angeles',
  organization: 'GTT Communications',
  asn: 3257,
  isProxy: proxy,
  isVpn: vpn,
  isTor: tor,
  isAbuser: abuser,
  source: 'ipapi.is',
);

void main() {
  test('residential, mobile and business count as clean like FlClash', () {
    for (final type in ['residential', 'mobile', 'business']) {
      expect(build(type: type).level, 'good');
    }
    expect(build(type: 'hosting').level, 'normal');
  });

  test('Tor exits and abuse reports are risky regardless of type', () {
    expect(build(type: 'residential', tor: true).level, 'risky');
    expect(build(type: 'business', abuser: true).level, 'risky');
  });

  test('score drops with each risk flag and stays in range', () {
    expect(build().score, 90);
    expect(build(type: 'hosting').score, 45);
    expect(build(proxy: true, vpn: true).score, 70);
    expect(build(type: 'hosting', tor: true, abuser: true).score, 0);
  });

  test('type labels cover every value the gateway can return', () {
    expect(build(type: 'residential').typeLabel, '原生家宽');
    expect(build(type: 'mobile').typeLabel, '移动网络');
    expect(build(type: 'business').typeLabel, '商业宽带');
    expect(build(type: 'hosting').typeLabel, '机房 IP');
  });

  test('parses the gateway payload', () {
    final quality = IpQuality.fromJson(const {
      'ip': '1.2.3.4',
      'type': 'hosting',
      'country': 'Japan',
      'city': 'Tokyo',
      'organization': 'Example',
      'asn': 64500,
      'isProxy': true,
      'isVpn': false,
      'isTor': false,
      'isAbuser': false,
      'source': 'ipapi.is',
    });
    expect(quality.level, 'normal');
    expect(quality.flags, ['代理标记']);
    expect(quality.score, 35);
  });
}
