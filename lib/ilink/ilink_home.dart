import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/ilink/dashboard_page.dart';
import 'package:luci_mobile/ilink/files_page.dart';
import 'package:luci_mobile/ilink/ilink_controller.dart';
import 'package:luci_mobile/ilink/ilink_theme.dart';
import 'package:luci_mobile/ilink/ilink_widgets.dart';
import 'package:luci_mobile/ilink/proxy_page.dart';
import 'package:luci_mobile/ilink/tools_page.dart';
import 'package:prism_ui/prism_ui.dart' as p;

class ILinkHome extends ConsumerStatefulWidget {
  const ILinkHome({super.key});

  @override
  ConsumerState<ILinkHome> createState() => _ILinkHomeState();
}

class _ILinkHomeState extends ConsumerState<ILinkHome>
    with WidgetsBindingObserver {
  int _index = 0;

  /// -1 or 1: the direction the new tab slides in from.
  double _slideFrom = 1;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.read(iLinkProvider).refresh(silent: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      ref.read(iLinkProvider).refresh(silent: true);
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(iLinkProvider);
    final data = state.data;
    if (data == null) {
      if (state.loading) return const ILinkLoading();
      return ILinkPage(
        title: 'iLink',
        children: [
          const SizedBox(height: 70),
          ILinkMessage(state.error ?? '暂时无法获取路由器状态'),
          p.FilledButton(
            onPressed: state.loading ? null : () => state.refresh(),
            child: const Text('重新连接'),
          ),
          p.TextButton(
            onPressed: state.startEditing,
            child: const Text('检查连接设置'),
          ),
        ],
      );
    }

    final pages = <Widget>[
      const DashboardPage(),
      const ProxyPage(),
      const FilesPage(),
      const ToolsPage(),
    ];
    final destinations = const [
      p.NavigationDockDestination(glyph: ILinkGlyphs.dashboard, label: '概览'),
      p.NavigationDockDestination(glyph: ILinkGlyphs.proxy, label: '代理'),
      p.NavigationDockDestination(glyph: ILinkGlyphs.files, label: '文件'),
      p.NavigationDockDestination(glyph: ILinkGlyphs.tools, label: '工具'),
    ];
    return p.Surface(
      color: p.SurfaceLevel.page.colorOf(p.Theme.of(context).colorScheme),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Tabs keep their state; the switcher only animates which one is
          // visible, sliding in from the direction of travel like FlClash.
          p.BottomInsetScope(
            inset: p.NavigationDock.insetOf(context),
            child: TweenAnimationBuilder<double>(
              // Restarting from 0 on every switch slides the new tab in from
              // the side of travel instead of swapping hard.
              key: ValueKey(_index),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) => Opacity(
                opacity: t.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(_slideFrom * 24 * (1 - t), 0),
                  child: child,
                ),
              ),
              child: IndexedStack(index: _index, children: pages),
            ),
          ),
          PositionedDirectional(
            start: 0,
            end: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: p.NavigationDock(
                  destinations: destinations,
                  selectedIndex: _index,
                  onSelected: (index) => setState(() {
                    _slideFrom = index > _index ? 1 : -1;
                    _index = index;
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
