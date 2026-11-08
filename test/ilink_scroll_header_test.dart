import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:luci_mobile/ilink/ilink_l10n.dart';
import 'package:luci_mobile/ilink/ilink_theme.dart';
import 'package:luci_mobile/ilink/ilink_widgets.dart';

Widget host(Widget child) => p.PrismApp(
  theme: ILinkTheme.of(Brightness.dark),
  darkTheme: ILinkTheme.of(Brightness.dark),
  themeMode: p.ThemeMode.dark,
  builder: (context, inner) {
    final size = MediaQuery.sizeOf(context);
    return p.ViewScope(size: size, isMobile: true, child: inner!);
  },
  localizationsDelegates: const [ILinkUiLocalizations.delegate],
  home: child,
);

double headerOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(ILinkPage),
        matching: find.byType(AnimatedOpacity),
      ).first,
    )
    .opacity;

void main() {
  testWidgets('content rests below the safe area, then runs under it on scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(
        ILinkPage(
          title: '概览',
          children: [
            const ILinkCard(child: Text('第一项')),
            for (var i = 0; i < 12; i++) const ILinkCard(child: Text('占位')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Resting: header opaque, content pushed below status bar + bar.
    expect(headerOpacity(tester), 1);
    final spacer = tester.widget<SizedBox>(
      find.descendant(of: find.byType(ListView), matching: find.byType(SizedBox)).first,
    );
    expect(spacer.height, 47 + ILinkPage.barHeight + 8);

    // Scrolled: header fades out so content can run under the status bar.
    await tester.drag(find.byType(ListView), const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(headerOpacity(tester), 0);

    // Back at the top: the resting layout returns.
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(headerOpacity(tester), 1);
    expect(tester.takeException(), isNull);
  });
}
