import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/ilink/ilink_controller.dart';
import 'package:luci_mobile/ilink/ilink_network_rollback.dart';
import 'package:luci_mobile/ilink/ilink_theme.dart';
import 'package:luci_mobile/ilink/ilink_widgets.dart';
import 'package:prism_ui/icons/icons.dart' as icons;
import 'package:prism_ui/prism_ui.dart' as p;

/// Everything that configures iLink itself, kept away from the tools that act
/// on the router.
class ILinkSettingsPage extends ConsumerStatefulWidget {
  const ILinkSettingsPage({super.key});

  @override
  ConsumerState<ILinkSettingsPage> createState() => _ILinkSettingsPageState();
}

class _ILinkSettingsPageState extends ConsumerState<ILinkSettingsPage> {
  bool _confirmClear = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(iLinkProvider);
    final profile = state.profile;
    final muted = p.Theme.of(context).colorScheme.onSurfaceVariant;
    return ILinkPage(
      title: '设置',
      children: [
        const ILinkSectionTitle('连接'),
        ILinkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ILinkKeyValue(
                '局域网',
                profile?.lanUrl.isNotEmpty == true ? profile!.lanUrl : '未配置',
              ),
              ILinkKeyValue(
                'DDNSTO',
                profile?.remoteUrl.isNotEmpty == true
                    ? profile!.remoteUrl
                    : '未配置',
              ),
              ILinkKeyValue('传输', state.data?.transport ?? '—'),
              const SizedBox(height: 12),
              p.OutlinedButton(
                onPressed: state.startEditing,
                child: const Text('修改连接设置'),
              ),
            ],
          ),
        ),
        const ILinkSectionTitle('网络配置回滚'),
        const ILinkNetworkRollbackCard(),
        const ILinkSectionTitle('外观'),
        ILinkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('主题', style: p.AppTextStyle.subheadline.of(context)),
              const SizedBox(height: 8),
              p.SegmentedControl<String>(
                segments: const [
                  ('light', '浅色'),
                  ('dark', '深色'),
                  ('system', '跟随'),
                ],
                value: state.themeMode,
                onChanged: (value) => state.setThemeMode(value),
              ),
              const SizedBox(height: 16),
              Text(
                'Liquid Glass',
                style: p.AppTextStyle.subheadline.of(context),
              ),
              const SizedBox(height: 8),
              p.SegmentedControl<bool>(
                segments: const [(true, '标准'), (false, '关闭')],
                value: state.glassEnabled,
                onChanged: (value) => state.setGlass(value),
              ),
            ],
          ),
        ),
        const ILinkSectionTitle('本机配置'),
        ILinkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_confirmClear) ...[
                Text(
                  '清除本机保存的地址与设备凭据？路由器上的凭据仍然有效，可单独撤销。',
                  style: p.AppTextStyle.footnote.of(context),
                ),
                const SizedBox(height: 16),
                p.FilledButton(
                  onPressed: state.clear,
                  child: const Text('确认清除'),
                ),
                p.TextButton(
                  onPressed: () => setState(() => _confirmClear = false),
                  child: const Text('取消'),
                ),
              ] else
                p.OutlinedButton(
                  onPressed: () => setState(() => _confirmClear = true),
                  child: const Text('清除本机配置'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'iLink v0.9.0\n基于 LuCI Mobile 与 Prism UI · GPL-3.0\n固定业务接口 · 最小权限',
            textAlign: TextAlign.center,
            style: p.AppTextStyle.caption1.of(context).copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}

/// Opens the settings page from a page bar action.
Future<void> openSettings(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const ILinkSettingsPage()));

/// Full-width entry to settings, pinned above the tools list.
class ILinkSettingsBar extends StatelessWidget {
  const ILinkSettingsBar({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = p.Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: p.PressSurface(
        fill: p.SurfaceLevel.card.colorOf(scheme),
        shape: p.AppShape.all(20),
        onPressed: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              icons.GlyphIcon(
                ILinkGlyphs.settings,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '设置',
                  style: p.AppTextStyle.subheadline.of(context),
                ),
              ),
              Text(
                '连接 · 外观 · 网络回滚',
                style: p.AppTextStyle.caption1
                    .of(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 6),
              Text(
                '›',
                style: p.AppTextStyle.subheadline
                    .of(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
