import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter/widgets.dart';
import 'package:luci_mobile/ilink/ilink_feature_api.dart';
import 'package:luci_mobile/ilink/ilink_widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;

/// Shell console: commands run as root on the router through the privileged
/// helper. Kept behind an explicit warning because it bypasses every other
/// restriction the gateway enforces.
class ILinkTerminalPage extends StatefulWidget {
  const ILinkTerminalPage({super.key, required this.service});

  final SystemInfoService service;

  @override
  State<ILinkTerminalPage> createState() => _ILinkTerminalPageState();
}

class _ILinkTerminalPageState extends State<ILinkTerminalPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<({String command, String output, bool failed})> _history = [];
  bool _truncated = false;
  bool _running = false;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final command = _controller.text.trim();
    if (command.isEmpty || _running) return;
    setState(() => _running = true);
    _controller.clear();
    try {
      final result = await widget.service.exec(command);
      if (!mounted) return;
      setState(() {
        _truncated = result.truncated;
        _history.add((
          command: command,
          output: result.output,
          failed: result.code != 0,
        ));
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _truncated = false;
        _history.add((
          command: command,
          output: error.toString(),
          failed: true,
        ));
      });
    } finally {
      if (mounted) setState(() => _running = false);
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      height: 1.45,
      color: p.Theme.of(context).colorScheme.onSurface,
    );
    return ILinkPage(
      title: '终端',
      children: [
        ILinkCard(
          child: Text(
            '命令以 root 身份在路由器上执行，最长 30 秒，输出最多保留 64 KB。'
            '这里能做的事和 SSH 一样，请只运行你理解的命令。',
            style: p.AppTextStyle.caption1
                .of(context)
                .copyWith(
                  color: p.Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        const SizedBox(height: 12),
        ILinkCard(
          child: SizedBox(
            height: 340,
            child: _history.isEmpty
                ? const ILinkEmpty('还没有执行过命令')
                : ListView.builder(
                    controller: _scroll,
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final entry = _history[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '\$ ${entry.command}',
                              style: mono.copyWith(
                                color: p.Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SelectionArea(
                              child: Text(
                                entry.output.isEmpty ? '(无输出)' : entry.output,
                                style: mono.copyWith(
                                  color: entry.failed
                                      ? p.Theme.of(context).colorScheme.error
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 12),
        ILinkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              p.TextField(
                controller: _controller,
                decoration: const p.InputDecoration(hintText: 'uptime'),
                onSubmitted: (_) => _run(),
                autocorrect: false,
                enableSuggestions: false,
              ),
              if (_truncated)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '输出超过 64 KB，只显示前面部分',
                    style: p.AppTextStyle.caption1
                        .of(context)
                        .copyWith(
                          color: p.Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              const SizedBox(height: 10),
              p.FilledButton(
                onPressed: _running ? null : _run,
                child: Text(_running ? '执行中…' : '执行'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Entry point shown in the tools list.
class ILinkTerminalTile extends StatelessWidget {
  const ILinkTerminalTile({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ILinkCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('终端', style: p.AppTextStyle.headline.of(context)),
                  const SizedBox(height: 4),
                  Text(
                    '以 root 运行路由器命令',
                    style: p.AppTextStyle.caption1
                        .of(context)
                        .copyWith(
                          color: p.Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(
              IconData(0xe5cc, fontFamily: 'MaterialIcons'),
              size: 18,
              textDirection: TextDirection.ltr,
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> confirmTerminal(BuildContext context) async {
  final confirmed = await p.showFloatingDialog<bool>(
    context: context,
    child: p.AlertDialog(
      title: '打开终端？',
      destructive: true,
      actions: [
        p.TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        p.TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('继续'),
        ),
      ],
      child: const Text(
        '终端里的命令以 root 执行，可以修改或删除路由器上的任何文件。'
        '只运行你理解的命令。',
      ),
    ),
  );
  return confirmed == true;
}
