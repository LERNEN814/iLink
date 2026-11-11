import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:luci_mobile/ilink/ilink_feature_api.dart';
import 'package:luci_mobile/ilink/ilink_feature_models.dart';
import 'package:luci_mobile/ilink/ilink_widgets.dart';
import 'package:luci_mobile/ilink/ilink_models.dart';
import 'package:prism_ui/prism_ui.dart' as p;

/// One plotted point: bytes per second down and up.
class TrafficPoint {
  const TrafficPoint(this.rx, this.tx);

  final double rx;
  final double tx;
}

/// Live WAN throughput: counters are sampled once per second and plotted as
/// two lines sharing one axis, scaled to the busiest recent sample.
class ILinkTrafficCard extends StatefulWidget {
  const ILinkTrafficCard({super.key, required this.service, this.samples = 60});

  final SystemInfoService service;
  final int samples;

  @override
  State<ILinkTrafficCard> createState() => _ILinkTrafficCardState();
}

class _ILinkTrafficCardState extends State<ILinkTrafficCard> {
  final List<TrafficPoint> _points = [];
  TrafficSample? _previous;
  Timer? _timer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final sample = await widget.service.traffic();
      if (!mounted) return;
      final previous = _previous;
      _previous = sample;
      if (previous == null || sample.at <= previous.at) return;
      final seconds = sample.at - previous.at;
      // A router restart or a counter wrap would otherwise plot a spike.
      final rx = sample.rx >= previous.rx
          ? (sample.rx - previous.rx) / seconds
          : 0.0;
      final tx = sample.tx >= previous.tx
          ? (sample.tx - previous.tx) / seconds
          : 0.0;
      setState(() {
        _error = null;
        _points.add(TrafficPoint(rx, tx));
        if (_points.length > widget.samples) _points.removeAt(0);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  /// Scale hint: the chart is normalised to the busiest recent sample.
  String get _peakLabel {
    if (_points.isEmpty) return 'WAN';
    var peak = 0.0;
    for (final point in _points) {
      if (point.rx > peak) peak = point.rx;
      if (point.tx > peak) peak = point.tx;
    }
    return '峰值 ${formatBytes(peak.round())}/s';
  }

  @override
  Widget build(BuildContext context) {
    final latest = _points.isEmpty ? null : _points.last;
    return ILinkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('实时流量', style: p.AppTextStyle.headline.of(context)),
              ),
              Text(
                _peakLabel,
                style: p.AppTextStyle.caption1
                    .of(context)
                    .copyWith(
                      color: p.Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Rate(
                  label: '下行',
                  value: latest?.rx,
                  color: p.Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Rate(
                  label: '上行',
                  value: latest?.tx,
                  color: p.Theme.of(context).colorScheme.tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 88,
            child: _error != null
                ? Center(
                    child: Text(
                      '流量不可用',
                      style: p.AppTextStyle.caption1
                          .of(context)
                          .copyWith(
                            color: p.Theme.of(context).colorScheme.error,
                          ),
                    ),
                  )
                : CustomPaint(
                    size: Size.infinite,
                    painter: _TrafficPainter(
                      points: List.of(_points),
                      capacity: widget.samples,
                      down: p.Theme.of(context).colorScheme.primary,
                      up: p.Theme.of(context).colorScheme.tertiary,
                      grid: p.Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Rate extends StatelessWidget {
  const _Rate({required this.label, required this.value, required this.color});

  final String label;
  final double? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label ${value == null ? '—' : '${formatBytes(value!.round())}/s'}',
          style: p.AppTextStyle.subheadline.of(context),
        ),
      ],
    );
  }
}

class _TrafficPainter extends CustomPainter {
  _TrafficPainter({
    required this.points,
    required this.capacity,
    required this.down,
    required this.up,
    required this.grid,
  });

  final List<TrafficPoint> points;
  final int capacity;
  final Color down;
  final Color up;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;

    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (points.length < 2) return;

    var peak = 1.0;
    for (final point in points) {
      peak = math.max(peak, math.max(point.rx, point.tx));
    }
    final step = size.width / (capacity - 1);
    final offset = size.width - (points.length - 1) * step;

    Path path(double Function(TrafficPoint) select) {
      final result = Path();
      for (var i = 0; i < points.length; i++) {
        final x = offset + i * step;
        final y =
            size.height -
            (select(points[i]) / peak).clamp(0.0, 1.0) * size.height;
        if (i == 0) {
          result.moveTo(x, y);
        } else {
          result.lineTo(x, y);
        }
      }
      return result;
    }

    canvas.drawPath(path((point) => point.rx), line..color = down);
    canvas.drawPath(path((point) => point.tx), line..color = up);
  }

  @override
  bool shouldRepaint(_TrafficPainter oldDelegate) =>
      oldDelegate.points.length != points.length ||
      (points.isNotEmpty &&
          oldDelegate.points.isNotEmpty &&
          (oldDelegate.points.last.rx != points.last.rx ||
              oldDelegate.points.last.tx != points.last.tx));
}
