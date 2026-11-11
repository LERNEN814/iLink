import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:luci_mobile/ilink/ilink_l10n.dart';
import 'package:luci_mobile/ilink/ilink_theme.dart';
import 'package:luci_mobile/ilink/ilink_widgets.dart';
import 'package:luci_mobile/ilink/ilink_models.dart';

Widget host(Widget child) => p.PrismApp(
  theme: ILinkTheme.of(Brightness.dark),
  darkTheme: ILinkTheme.of(Brightness.dark),
  themeMode: p.ThemeMode.dark,
  liquidGlass: p.LiquidGlassQuality.standard,
  builder: (context, child) {
    final size = MediaQuery.sizeOf(context);
    return p.ViewScope(size: size, isMobile: true, child: child!);
  },
  localizationsDelegates: const [ILinkUiLocalizations.delegate],
  supportedLocales: const [Locale('zh', 'CN')],
  home: child,
);

void main() {
  testWidgets('Prism navigation, glass and cards render together', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        p.Surface(
          child: Stack(
            children: [
              const ILinkPage(
                title: '概览',
                children: [
                  ILinkCard(child: Text('iStoreOS')),
                  ILinkStatusPill('DDNSTO'),
                ],
              ),
              const Align(
                alignment: Alignment.bottomCenter,
                child: p.NavigationDock(
                  destinations: [
                    p.NavigationDockDestination(
                      glyph: ILinkGlyphs.dashboard,
                      label: '概览',
                    ),
                    p.NavigationDockDestination(
                      glyph: ILinkGlyphs.network,
                      label: '网络',
                    ),
                  ],
                  selectedIndex: 0,
                  onSelected: _select,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('iStoreOS'), findsOneWidget);
    expect(find.text('DDNSTO'), findsOneWidget);
    expect(find.text('网络'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('status models never assume optional fields exist', () {
    final data = ILinkData(
      status: {},
      clients: [],
      interfaces: [],
      transport: 'DDNSTO',
      fetchedAt: _epoch,
    );
    expect(data.memoryUsage, 0);
    expect(data.hostname, 'iStoreOS');
    expect(data.onlineInterfaces, 0);
  });
}

void _select(int _) {}
final _epoch = DateTime.fromMillisecondsSinceEpoch(0);
