import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:prism_ui/prism_ui.dart' as p;

/// Fullscreen libmpv player for gateway file streams. The URL already carries
/// a short-lived stream ticket, so the device token never reaches mpv.
class ILinkVideoPlayerPage extends StatefulWidget {
  const ILinkVideoPlayerPage({
    super.key,
    required this.url,
    required this.title,
    required this.verifyTls,
  });

  final String url;
  final String title;

  /// False only for LAN hosts with self-signed certificates.
  final bool verifyTls;

  @override
  State<ILinkVideoPlayerPage> createState() => _ILinkVideoPlayerPageState();
}

class _ILinkVideoPlayerPageState extends State<ILinkVideoPlayerPage> {
  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _open();
  }

  Future<void> _open() async {
    final platform = _player.platform;
    if (!widget.verifyTls && platform is NativePlayer) {
      // Newer and older mpv cores spell the option differently; unknown
      // properties fail silently, which is acceptable.
      await platform.setProperty('network-tls-verify', 'no');
      await platform.setProperty('tls-verify', 'no');
    }
    await _player.open(Media(widget.url));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return p.Surface(
      color: const Color(0xFF000000),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Video(
              controller: _controller,
              // The page provides its own chrome; the widget's default
              // Material controls handle gestures, seek bar and fullscreen.
              controls: AdaptiveVideoControls,
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    p.IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        IconData(0xe5c4, fontFamily: 'MaterialIcons'),
                        color: Color(0xFFFFFFFF),
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFFFFFF),
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
