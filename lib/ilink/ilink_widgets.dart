import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:prism_ui/icons/icons.dart' as icons;
import 'package:luci_mobile/ilink/ilink_theme.dart';

final _barChanges = Listenable.merge(const []);
final _barIdle = ValueNotifier<bool>(false);

PreferredSizeWidget buildILinkBar({
  required String title,
  List<Widget> actions = const [],
}) => p.ScaffoldBar(
  isCompact: false,
  listenable: _barChanges,
  loading: _barIdle,
  builder: (_) => p.AppBar(title: Text(title), actions: actions),
);

/// Page shell with two top-area modes.
///
/// Resting at the top, content starts below the status bar and the header area
/// is opaque. Once the page scrolls past a small threshold, the header fades
/// and content runs under a transparent status bar. Scrolling back to the very
/// top returns to the resting layout.
class ILinkPage extends StatefulWidget {
  const ILinkPage({
    super.key,
    required this.title,
    required this.children,
    this.onRefresh,
    this.refreshing = false,
    this.scroll = true,
    this.action,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback? onRefresh;
  final bool refreshing;
  final bool scroll;

  /// Extra page-bar button, drawn before the refresh control.
  final Widget? action;

  /// A phone page bar's height, matching prism_ui's page toolbar.
  static const barHeight = 72.0;

  @override
  State<ILinkPage> createState() => _ILinkPageState();
}

class _ILinkPageState extends State<ILinkPage> {
  bool _collapsed = false;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final pixels = notification.metrics.pixels;
    final next = _collapsed ? pixels > 0.5 : pixels > 8;
    if (next != _collapsed) setState(() => _collapsed = next);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = p.Theme.of(context).colorScheme;
    final pageColor = p.SurfaceLevel.page.colorOf(scheme);
    final statusInset = MediaQuery.paddingOf(context).top;
    final headerHeight = statusInset + ILinkPage.barHeight;
    final dark = scheme.brightness == Brightness.dark;

    final header = IgnorePointer(
      ignoring: _collapsed,
      child: AnimatedOpacity(
        opacity: _collapsed ? 0 : 1,
        duration: const Duration(milliseconds: 160),
        child: Container(
          height: headerHeight,
          color: pageColor,
          padding: EdgeInsets.only(top: statusInset),
          child: SizedBox(
            height: ILinkPage.barHeight,
            child: Row(
              children: [
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: p.AppTextStyle.pageTitle.of(context),
                  ),
                ),
                if (widget.action != null) ...[
                  widget.action!,
                  const SizedBox(width: 4),
                ],
                if (widget.onRefresh != null) ...[
                  p.AppBarActionButton(
                    data: p.IconButtonData(
                      glyph: ILinkGlyphs.refresh,
                      tooltip: '刷新',
                      isLoading: widget.refreshing,
                      onPressed: widget.onRefresh,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    final body = Stack(
      fit: StackFit.expand,
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.scroll
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    20,
                    0,
                    20,
                    138 + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    SizedBox(height: headerHeight + 8),
                    ...widget.children,
                  ],
                )
              : Padding(
                  padding: EdgeInsets.only(top: headerHeight),
                  child: Column(children: widget.children),
                ),
        ),
        Align(alignment: Alignment.topCenter, child: header),
      ],
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: const Color(0x00000000),
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: pageColor,
      ),
      child: p.PrismScaffold(
        bar: const _NoBar(),
        backgroundColor: pageColor,
        body: body,
      ),
    );
  }
}

/// Keeps [p.PrismScaffold]'s layout while ILinkPage draws its own header.
class _NoBar extends StatelessWidget implements PreferredSizeWidget {
  const _NoBar();

  @override
  Size get preferredSize => Size.zero;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class ILinkCard extends StatelessWidget {
  const ILinkCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = p.Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: padding,
      decoration: ShapeDecoration(
        color: color ?? p.SurfaceLevel.card.colorOf(scheme),
        shape: p.AppShape.all(28),
        shadows: [
          BoxShadow(
            color: scheme.shadow.withValues(
              alpha: scheme.brightness == Brightness.dark ? 0.35 : 0.08,
            ),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// A card whose body collapses behind its header row.
class ILinkExpandableCard extends StatelessWidget {
  const ILinkExpandableCard({
    super.key,
    required this.title,
    required this.summary,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final String summary;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = p.Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: ShapeDecoration(
        color: p.SurfaceLevel.card.colorOf(scheme),
        shape: p.AppShape.all(28),
        shadows: [
          BoxShadow(
            color: scheme.shadow.withValues(
              alpha: scheme.brightness == Brightness.dark ? 0.35 : 0.08,
            ),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          p.PressSurface(
            fill: const Color(0x00000000),
            shape: p.AppShape.all(28),
            onPressed: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: p.AppTextStyle.headline.of(context)),
                        const SizedBox(height: 4),
                        Text(
                          summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: p.AppTextStyle.caption1
                              .of(context)
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: icons.GlyphIcon(
                      ILinkGlyphs.chevronDown,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class ILinkSectionTitle extends StatelessWidget {
  const ILinkSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
    child: Text(
      text,
      style: p.AppTextStyle.footnote
          .of(context, emphasized: true)
          .copyWith(color: p.Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

class ILinkMetric extends StatelessWidget {
  const ILinkMetric({
    super.key,
    required this.label,
    required this.value,
    this.detail,
  });

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) => ILinkCard(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: p.AppTextStyle.caption1
              .of(context)
              .copyWith(
                color: p.Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            value,
            style: p.AppTextStyle.title2.of(context, emphasized: true),
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(
            detail!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: p.AppTextStyle.caption2
                .of(context)
                .copyWith(
                  color: p.Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    ),
  );
}

class ILinkKeyValue extends StatelessWidget {
  const ILinkKeyValue(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: p.AppTextStyle.footnote
                .of(context)
                .copyWith(
                  color: p.Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        Expanded(
          child: Text(value, style: p.AppTextStyle.footnote.of(context)),
        ),
      ],
    ),
  );
}

class ILinkStatusPill extends StatelessWidget {
  const ILinkStatusPill(this.text, {super.key, this.online = true});

  final String text;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final scheme = p.Theme.of(context).colorScheme;
    final color = online ? scheme.success : scheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.12),
        shape: p.AppShape.full,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            text,
            style: p.AppTextStyle.caption1
                .of(context, emphasized: true)
                .copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class ILinkMessage extends StatelessWidget {
  const ILinkMessage(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = p.Theme.of(context).colorScheme;
    return ILinkCard(
      color: scheme.errorContainer.withValues(alpha: 0.55),
      child: Text(
        text,
        style: p.AppTextStyle.footnote
            .of(context)
            .copyWith(color: scheme.onErrorContainer),
      ),
    );
  }
}

class ILinkLoading extends StatelessWidget {
  const ILinkLoading({super.key, this.label = '正在连接 iStoreOS'});

  final String label;

  @override
  Widget build(BuildContext context) => p.Surface(
    color: p.SurfaceLevel.page.colorOf(p.Theme.of(context).colorScheme),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const p.ActivityIndicator(size: 28),
          const SizedBox(height: 18),
          Text(label, style: p.AppTextStyle.subheadline.of(context)),
        ],
      ),
    ),
  );
}

class ILinkEmpty extends StatelessWidget {
  const ILinkEmpty(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Center(
      child: Column(
        children: [
          icons.GlyphIcon(
            ILinkGlyphs.clients,
            size: 38,
            color: p.Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 14),
          Text(text, style: p.AppTextStyle.subheadline.of(context)),
        ],
      ),
    ),
  );
}
