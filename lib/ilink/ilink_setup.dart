import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:luci_mobile/ilink/ilink_api.dart';
import 'package:luci_mobile/ilink/ilink_controller.dart';
import 'package:luci_mobile/ilink/ilink_models.dart';
import 'package:luci_mobile/ilink/ilink_widgets.dart';

class ILinkSetup extends ConsumerStatefulWidget {
  const ILinkSetup({super.key});

  @override
  ConsumerState<ILinkSetup> createState() => _ILinkSetupState();
}

class _ILinkSetupState extends ConsumerState<ILinkSetup> {
  late final TextEditingController _remote;
  late final TextEditingController _token;
  late final TextEditingController _lan;
  late final TextEditingController _fingerprint;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(iLinkProvider).profile;
    _remote = TextEditingController(text: profile?.remoteUrl ?? 'https://');
    _token = TextEditingController(text: profile?.token ?? '');
    _lan = TextEditingController(text: profile?.lanUrl ?? '');
    _fingerprint = TextEditingController(
      text: profile?.certificateSha256 ?? '',
    );
  }

  @override
  void dispose() {
    _remote.dispose();
    _token.dispose();
    _lan.dispose();
    _fingerprint.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final profile = ILinkProfile(
      remoteUrl: _remote.text.trim().replaceAll(RegExp(r'/$'), ''),
      token: _token.text.trim(),
      lanUrl: _lan.text.trim().replaceAll(RegExp(r'/$'), ''),
      certificateSha256: ILinkGatewayClient.normalizeFingerprint(
        _fingerprint.text,
      ),
    );
    await ref.read(iLinkProvider).save(profile);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(iLinkProvider);
    return p.PrismScaffold(
      bar: buildILinkBar(
        title: '连接 iStoreOS',
        actions: [
          if (state.profile != null)
            p.TextButton(
              onPressed: state.loading ? null : state.cancelEditing,
              child: const Text('取消'),
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          MediaQuery.paddingOf(context).top + ILinkPage.barHeight + 8,
          20,
          40,
        ),
        children: [
          Text(
            'iLink',
            style: p.AppTextStyle.largeTitle.of(context, emphasized: true),
          ),
          const SizedBox(height: 6),
          Text(
            '安全地连接你的路由器，无需暴露 LuCI 或 root 登录。',
            style: p.AppTextStyle.subheadline
                .of(context)
                .copyWith(
                  color: p.Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          if (state.error != null) ILinkMessage(state.error!),
          ILinkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DDNSTO 远程连接', style: p.AppTextStyle.headline.of(context)),
                const SizedBox(height: 18),
                p.TextFormField(
                  controller: _remote,
                  keyboardType: TextInputType.url,
                  decoration: const p.InputDecoration(
                    hintText: 'https://你的前缀.ddnsto.com',
                    helperText: 'DDNSTO 应映射到网关的 127.0.0.1:8089',
                  ),
                ),
                const SizedBox(height: 16),
                p.SecretTextFormField(
                  controller: _token,
                  decoration: const p.InputDecoration(
                    hintText: '设备凭据（安装网关时生成）',
                  ),
                ),
              ],
            ),
          ),
          ILinkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('局域网直连（可选）', style: p.AppTextStyle.headline.of(context)),
                const SizedBox(height: 6),
                Text(
                  '配置后优先走局域网，失败时切换 DDNSTO。',
                  style: p.AppTextStyle.footnote
                      .of(context)
                      .copyWith(
                        color: p.Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 18),
                p.TextFormField(
                  controller: _lan,
                  keyboardType: TextInputType.url,
                  decoration: const p.InputDecoration(
                    hintText: 'https://192.168.100.1:8443',
                  ),
                ),
                const SizedBox(height: 16),
                p.TextFormField(
                  controller: _fingerprint,
                  decoration: const p.InputDecoration(
                    hintText: 'LAN 证书 SHA-256 指纹',
                    helperText: '只信任匹配的证书，不会关闭证书校验',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: p.FilledButton(
              onPressed: state.loading ? null : _save,
              child: Text(state.loading ? '正在验证连接…' : '保存并连接'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '凭据仅保存在 Android 安全存储中。v0.1 所有接口均为只读。',
            textAlign: TextAlign.center,
            style: p.AppTextStyle.caption1
                .of(context)
                .copyWith(
                  color: p.Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
