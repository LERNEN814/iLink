import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:luci_mobile/ilink/ilink_controller.dart';
import 'package:luci_mobile/ilink/ilink_home.dart';
import 'package:luci_mobile/ilink/ilink_l10n.dart';
import 'package:luci_mobile/ilink/ilink_models.dart';
import 'package:luci_mobile/ilink/ilink_theme.dart';
import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/models/interface.dart';

void main() {
  testWidgets('all four iLink tabs render real gateway-shaped data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ILinkController()
      ..profile = ILinkProfile(
        remoteUrl: 'https://home.ddnsto.com',
        token: 'a' * 64,
      )
      ..data = ILinkData(
        status: const {
          'hostname': 'iStoreOS',
          'model': 'NanoPi R3S',
          'release': 'iStoreOS 24.10',
          'kernel': '6.6',
          'uptime': 3600,
          'load': [0.12],
          'memory': {'total': 1000, 'available': 250},
        },
        clients: [
          Client.fromLease(const {
            'hostname': 'phone',
            'ipaddr': '192.168.100.2',
            'macaddr': '00:11:22:33:44:55',
          }),
        ],
        interfaces: [
          NetworkInterface.fromJson(const {
            'interface': 'lan',
            'up': true,
            'proto': 'static',
            'device': 'br-lan',
          }),
        ],
        wireless: const [],
        transport: 'DDNSTO',
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [iLinkProvider.overrideWith((ref) => controller)],
        child: p.PrismApp(
          theme: ILinkTheme.of(Brightness.light),
          darkTheme: ILinkTheme.of(Brightness.dark),
          localizationsDelegates: const [ILinkUiLocalizations.delegate],
          builder: (context, child) {
            final size = MediaQuery.sizeOf(context);
            return p.ViewScope(size: size, isMobile: true, child: child!);
          },
          home: const ILinkHome(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('路由器运行正常'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);

    expect(find.text('phone'), findsOneWidget);
    expect(find.text('192.168.100.2'), findsOneWidget);
    expect(find.text('未获取到无线网络信息'), findsOneWidget);
    expect(find.text('br-lan'), findsOneWidget);
    expect(find.text('代理'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);

    await tester.tap(find.text('工具'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text(
        'iLink v0.2.0\n基于 LuCI Mobile 与 Prism UI · GPL-3.0\n固定业务接口 · 最小权限',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
