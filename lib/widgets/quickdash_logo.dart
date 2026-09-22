import 'package:flutter/material.dart';

/// HotBite brand colours, taken from the logo lockup.
class HotBiteBrand {
  HotBiteBrand._();
  static const blueLight = Color(0xFF2E6BE6);
  static const blueDark = Color(0xFF0F3BBF);
  static const orange = Color(0xFFFF8A00);
  static const orangeDeep = Color(0xFFF5401A);
}

/// The HotBite mark: the Q with a cloche in its counter, the arrow tail, and
/// the speed lines trailing off to the left.
///
/// Drawn rather than shipped as a PNG. It stays sharp at every density and
/// needs no asset to decode before the splash can appear. [monochrome] draws
/// the same shape in a single colour — the brand blue disappears against
/// Midnight Navy, so a dark background needs a white version of it.
class HotBiteMark extends StatelessWidget {
  const HotBiteMark({super.key, this.size = 120, this.monochrome});

  final double size;
  final Color? monochrome;

  @override
  Widget build(BuildContext context) {
    // The real HotBite Delivery logo (flame + scooter lockup). Transparent
    // background, so it sits on any container. Replaces the old hand-drawn
    // "Q" mark that looked like the previous brand.
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/images/hotbite_logo.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// "HotBite" — blue through "Quick", orange through "Dash", as on the
/// lockup. One gradient with a hard stop rather than two text spans, so the
/// colour break stays put whatever the font metrics do.
class HotBiteWordmark extends StatelessWidget {
  const HotBiteWordmark({super.key, this.fontSize = 40, this.monochrome});

  final double fontSize;
  final Color? monochrome;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      'HotBite',
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        fontStyle: FontStyle.italic,
        letterSpacing: -fontSize * 0.02,
        height: 1.05,
        color: monochrome ?? Colors.white,
      ),
    );
    if (monochrome != null) return text;

    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        colors: [
          HotBiteBrand.blueLight,
          HotBiteBrand.blueDark,
          HotBiteBrand.orange,
          HotBiteBrand.orangeDeep,
        ],
        stops: [0.0, 0.55, 0.57, 1.0],
      ).createShader(rect),
      blendMode: BlendMode.srcIn,
      child: text,
    );
  }
}

/// The full lockup: mark over wordmark, optionally with the tagline.
class HotBiteLogo extends StatelessWidget {
  const HotBiteLogo({
    super.key,
    this.width = 240,
    this.showTagline = false,
    this.monochrome,
  });

  final double width;
  final bool showTagline;
  final Color? monochrome;

  @override
  Widget build(BuildContext context) {
    final wordSize = width * 0.20;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        HotBiteMark(size: width * 0.86, monochrome: monochrome),
        SizedBox(height: width * 0.02),
        HotBiteWordmark(fontSize: wordSize, monochrome: monochrome),
        if (showTagline) ...[
          SizedBox(height: width * 0.03),
          SizedBox(
            width: width,
            child: Text(
            'Quick to Order. Fast to Deliver.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: wordSize * 0.36,
              fontWeight: FontWeight.w800,
              fontStyle: FontStyle.italic,
              letterSpacing: 0.2,
              color: monochrome ?? HotBiteBrand.blueDark,
            ),
            ),
          ),
        ],
      ],
    );
  }
}
