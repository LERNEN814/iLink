library;

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:luci_mobile/ilink/ilink_controller.dart';
import 'package:luci_mobile/ilink/ilink_home.dart';
import 'package:luci_mobile/ilink/ilink_l10n.dart';
import 'package:luci_mobile/ilink/ilink_setup.dart';
import 'package:luci_mobile/ilink/ilink_theme.dart';
import 'package:luci_mobile/ilink/ilink_widgets.dart';

export 'package:luci_mobile/state/app_state_provider.dart'
    show appStateProvider;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // libmpv must be initialised before any Player is created.
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: ILinkApp()));
}

class ILinkApp extends ConsumerStatefulWidget {
  const ILinkApp({super.key});

  @override
  ConsumerState<ILinkApp> createState() => _ILinkAppState();
}

class _ILinkAppState extends ConsumerState<ILinkApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(ref.read(iLinkProvider).initialize);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(iLinkProvider);
    final themeMode = switch (state.themeIndex) {
      1 => p.ThemeMode.light,
      2 => p.ThemeMode.dark,
      _ => p.ThemeMode.system,
    };
    return p.PrismApp(
      title: 'iLink',
      debugShowCheckedModeBanner: false,
      theme: ILinkTheme.of(Brightness.light),
      darkTheme: ILinkTheme.of(Brightness.dark),
      themeMode: themeMode,
      liquidGlass: state.glassEnabled ? p.LiquidGlassQuality.standard : null,
      builder: (context, child) {
        final size = MediaQuery.sizeOf(context);
        return p.ViewScope(
          size: size,
          isMobile: size.width < 600,
          child: child!,
        );
      },
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        ILinkUiLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: !state.initialized
          ? const ILinkLoading(label: '正在启动 iLink')
          : state.profile == null || state.editing
          ? const ILinkSetup()
          : const ILinkHome(),
    );
  }
}
