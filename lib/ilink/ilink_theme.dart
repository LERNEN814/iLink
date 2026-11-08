import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:prism_ui/icons/glyph.dart';

/// Shared Prism theme. prism_ui is pinned to FlClash's submodule commit.
abstract final class ILinkTheme {
  static const seed = Color(0xFF5E5CE6);

  static p.ThemeData of(Brightness brightness) => p.ThemeData(
    colorScheme: p.ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      style: p.ColorStyle.vivid,
    ),
    fontFamilyFallback: const [
      'Noto Sans CJK SC',
      'Source Han Sans SC',
      'Microsoft YaHei',
      'sans-serif',
    ],
    elevatedColorScheme: brightness == Brightness.dark
        ? p.ColorScheme.fromSeed(
            seedColor: seed,
            brightness: brightness,
            style: p.ColorStyle.vivid,
          ).elevated
        : null,
  );
}

// The dashboard and tools glyphs are adapted from FlClash (GPL-3.0).
abstract final class ILinkGlyphs {
  static const proxy = Glyph([
    GlyphCircle(12, 12, 8.8),
    GlyphOval(8.2, 3.2, 15.8, 20.8, role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(3.2, 12),
      GlyphVertex(20.8, 12),
    ], role: GlyphRole.detail),
  ]);

  static const files = Glyph([
    GlyphPolyline([
      GlyphVertex(3.5, 6.5, 2.5),
      GlyphVertex(10, 6.5),
      GlyphVertex(13, 3.5),
      GlyphVertex(20.5, 3.5, 2.5),
      GlyphVertex(20.5, 20.5, 2.5),
      GlyphVertex(3.5, 20.5, 2.5),
    ], closed: true),
  ]);

  static const dashboard = Glyph([
    GlyphBox(3.5, 3.5, 10.5, 11.5, 2),
    GlyphBox(13.5, 3.5, 20.5, 9.5, 2),
    GlyphBox(3.5, 14.5, 10.5, 20.5, 2),
    GlyphBox(13.5, 12.5, 20.5, 20.5, 2),
  ]);

  static const network = Glyph([
    GlyphCircle(12, 12, 8.8),
    GlyphOval(8.2, 3.2, 15.8, 20.8, role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(3.2, 12),
      GlyphVertex(20.8, 12),
    ], role: GlyphRole.detail),
  ]);

  static const clients = Glyph([
    GlyphCircle(12, 5.2, 2.4),
    GlyphCircle(5.2, 17.6, 2.4),
    GlyphCircle(18.8, 17.6, 2.4),
    GlyphLink(Offset(12, 5.2), Offset(5.2, 17.6), 2.4),
    GlyphLink(Offset(12, 5.2), Offset(18.8, 17.6), 2.4),
    GlyphLink(Offset(5.2, 17.6), Offset(18.8, 17.6), 2.4),
  ]);

  static const tools = Glyph([
    GlyphBox(3, 7, 21, 20, 2.8),
    GlyphPolyline([
      GlyphVertex(9, 7),
      GlyphVertex(9, 4.6, 1.4),
      GlyphVertex(15, 4.6, 1.4),
      GlyphVertex(15, 7),
    ]),
    GlyphPolyline([
      GlyphVertex(3.2, 12.6),
      GlyphVertex(9.6, 12.6),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(14.4, 12.6),
      GlyphVertex(20.8, 12.6),
    ], role: GlyphRole.detail),
    GlyphBox(10.4, 11, 13.6, 14.4, 1, role: GlyphRole.detail),
  ]);

  static const chevronDown = Glyph([
    GlyphPolyline([
      GlyphVertex(5.5, 9.5),
      GlyphVertex(12, 16, 0.4),
      GlyphVertex(18.5, 9.5),
    ], role: GlyphRole.line),
  ]);

  static const refresh = Glyph([
    GlyphArc(12, 12, 8.3, -2.5, 4.7),
    GlyphPolyline([
      GlyphVertex(15.5, 3.7),
      GlyphVertex(20.2, 4.2, 0.6),
      GlyphVertex(19.6, 8.8),
    ]),
  ]);
}
