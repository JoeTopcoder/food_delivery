// Renders the QuickDash mark to PNGs.
//
//   flutter test test/render_logo_preview.dart
//
// Two jobs. It writes build/logo_preview_*.png for eyeballing the drawing
// without a device, and it writes assets/images/app_icon.png, which
// flutter_launcher_icons consumes to generate the Android and iOS launcher
// sets — so the icon is produced from the same code the app draws, and cannot
// drift from it.
//
// Note: text does NOT render meaningfully here. flutter_test substitutes a
// font that draws every glyph as a filled box, so the wordmark comes out as
// solid blocks. Only the painted mark is worth looking at; check the wordmark
// on a device.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_driver/widgets/quickdash_logo.dart';

Future<void> _shoot(
  WidgetTester tester,
  String path,
  Widget child, {
  Color background = Colors.white,
  double pixelRatio = 3.0,
  EdgeInsets padding = const EdgeInsets.all(24),
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: Container(
            color: background,
            padding: padding,
            child: Center(child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final out = File(path);
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('preview: mark on white', (t) async {
    await _shoot(
      t,
      'build/logo_preview_mark.png',
      const SizedBox(width: 320, child: QuickDashMark(size: 300)),
    );
  });

  testWidgets('preview: the splash card on Midnight Navy', (t) async {
    await _shoot(
      t,
      'build/logo_preview_splash.png',
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: const QuickDashMark(size: 168),
      ),
      background: const Color(0xFF0B1220),
    );
  });

  // The launcher source image. Square, generous margin — launcher shapes crop
  // hard, and an adaptive icon crops harder still.
  testWidgets('generate: app_icon.png', (t) async {
    await t.binding.setSurfaceSize(const Size(360, 360));
    await _shoot(
      t,
      'assets/images/app_icon.png',
      const SizedBox(
        width: 312,
        height: 312,
        child: Center(child: QuickDashMark(size: 250)),
      ),
      padding: EdgeInsets.zero,
      pixelRatio: 1024 / 312,
    );
  });
}
