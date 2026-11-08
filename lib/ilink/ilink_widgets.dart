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

class ILinkPage extends StatelessWidget {
  const ILinkPage({
    super.key,
    required this.title,
    required this.children,
    this.onRefresh,
    this.refreshing = false,
    this.scroll = true,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback? onRefresh;
  final bool refreshing;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final content = scroll
        ? ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.paddingOf(context).top + 8,
              20,
              138 + MediaQuery.paddingOf(context).bottom,
            ),
            children: children,
          )
        : Padding(
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
            child: Column(children: children),
          );
    return p.PrismScaffold(
      bar: buildILinkBar(
        title: title,
        actions: [
          if (onRefresh != null)
            p.AppBarActionButton(
              data: p.IconButtonData(
                glyph: ILinkGlyphs.refresh,
                tooltip: '刷新',
                isLoading: refreshing,
                onPressed: onRefresh,
              ),
            ),
        ],
      ),
      body: content,
    );
  }
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
