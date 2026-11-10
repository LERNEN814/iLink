import 'package:flutter/widgets.dart';
import 'package:luci_mobile/ilink/ilink_feature_api.dart';
import 'package:luci_mobile/ilink/ilink_feature_models.dart';
import 'package:luci_mobile/ilink/ilink_widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;

/// Exit address and reputation of the current proxy node, ported from
/// FlClash's IP quality lookup.
class ILinkIpQualityCard extends StatefulWidget {
  const ILinkIpQualityCard({super.key, required this.service});

  final OpenClashService service;

  @override
  State<ILinkIpQualityCard> createState() => _ILinkIpQualityCardState();
}

class _ILinkIpQualityCardState extends State<ILinkIpQualityCard> {
  IpQuality? _quality;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final quality = await widget.service.ipCheck();
      if (!mounted) return;
      setState(() => _quality = quality);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = p.Theme.of(context).colorScheme;
    final quality = _quality;
    final levelColor = switch (quality?.level) {
      'risky' => scheme.error,
      'normal' => scheme.tertiary,
      _ => scheme.primary,
    };
    return ILinkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '出口 IP',
                  style: p.AppTextStyle.headline.of(context),
                ),
              ),
              p.OutlinedButton(
                onPressed: _loading ? null : _load,
                child: Text(_loading ? '检测中…' : '重新检测'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_error != null)
            Text(
              '检测失败：$_error',
              style: p.AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: scheme.error),
            )
          else if (quality == null)
            Text(
              '正在通过代理查询出口地址…',
              style: p.AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    quality.ip,
                    style: p.AppTextStyle.title2
                        .of(context)
                        .copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: levelColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${quality.levelLabel} ${quality.score}',
                    style: p.AppTextStyle.caption1
                        .of(context)
                        .copyWith(
                          color: levelColor,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Tag(text: quality.typeLabel, color: levelColor),
                if (quality.country.isNotEmpty)
                  _Tag(
                    text: [
                      quality.country,
                      if (quality.city.isNotEmpty) quality.city,
                    ].join(' · '),
                    color: scheme.onSurfaceVariant,
                  ),
                for (final flag in quality.flags)
                  _Tag(text: flag, color: scheme.error),
              ],
            ),
            const SizedBox(height: 10),
            ILinkKeyValue(
              '归属',
              [
                if (quality.organization.isNotEmpty) quality.organization,
                if (quality.asn != null) 'AS${quality.asn}',
              ].join(' · '),
            ),
            ILinkKeyValue('数据来源', quality.source),
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: p.AppTextStyle.caption1.of(context).copyWith(color: color),
      ),
    );
  }
}
