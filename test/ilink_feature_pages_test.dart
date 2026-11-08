import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:luci_mobile/ilink/files_page.dart';
import 'package:luci_mobile/ilink/ilink_controller.dart';
import 'package:luci_mobile/ilink/ilink_feature_api.dart';
import 'package:luci_mobile/ilink/ilink_feature_models.dart';
import 'package:luci_mobile/ilink/ilink_l10n.dart';
import 'package:luci_mobile/ilink/ilink_models.dart';
import 'package:luci_mobile/ilink/ilink_theme.dart';
import 'package:luci_mobile/ilink/proxy_page.dart';

const _proxyData = OpenClashData(
  running: true,
  version: 'test-core',
  mode: 'rule',
  config: '/etc/openclash/config/test.yaml',
  mixedPort: 7893,
  groups: [
    ProxyGroup(
      name: 'Proxy Select',
      type: 'Selector',
      now: 'Node 1',
      nodes: [
        ProxyNode(name: 'Node 1', type: 'Shadowsocks', alive: true, delay: 88),
      ],
    ),
  ],
  connections: [
    ProxyConnection(
      id: 'abc-123',
      host: 'example.com:443',
      chain: ['Node 1', 'Proxy Select'],
      rule: 'MATCH',
      upload: 10,
      download: 20,
    ),
  ],
  upload: 10,
  download: 20,
  uploadTotal: 100,
  downloadTotal: 200,
);

const _entries = [
  FileEntry(name: 'docs', path: 'docs', directory: true, size: 0, modified: 0),
  FileEntry(
    name: 'note.txt',
    path: 'note.txt',
    directory: false,
    size: 5,
    modified: 0,
  ),
];

void main() {
  ILinkController controller() => ILinkController()
    ..profile = const ILinkProfile(
      remoteUrl: 'https://remote.invalid',
      token:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    )
    ..data = ILinkData(
      status: const {
        'mounts': [
          {'mount': '/mnt/data_sdb1', 'size': 1000, 'available': 500},
        ],
      },
      clients: const [],
      interfaces: const [],
      wireless: const [],
      transport: 'LAN',
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [iLinkProvider.overrideWith((ref) => controller())],
        child: p.PrismApp(
          theme: ILinkTheme.of(Brightness.light),
          darkTheme: ILinkTheme.of(Brightness.dark),
          builder: (context, child) {
            final size = MediaQuery.sizeOf(context);
            return p.ViewScope(size: size, isMobile: true, child: child!);
          },
          localizationsDelegates: const [ILinkUiLocalizations.delegate],
          home: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('proxy page renders groups, connections and config', (
    tester,
  ) async {
    await pump(tester, ProxyPage(service: OpenClashService.fake(_proxyData)));
    expect(find.text('OpenClash'), findsOneWidget);
    expect(find.text('Node 1'), findsWidgets);
    expect(find.textContaining('运行中'), findsOneWidget);

    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(find.text('example.com:443'), findsOneWidget);

    await tester.tap(find.text('配置'));
    await tester.pumpAndSettle();
    expect(find.text('test.yaml'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('files page lists entries and offers long-press actions', (
    tester,
  ) async {
    await pump(tester, FilesPage(service: FileService.fake(_entries)));
    expect(find.text('note.txt'), findsOneWidget);
    expect(find.text('docs'), findsOneWidget);

    await tester.longPress(find.text('note.txt'));
    await tester.pumpAndSettle();
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
