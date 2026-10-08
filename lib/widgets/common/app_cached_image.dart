import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Shared network image for lists/cards. Caches to disk+memory and decodes at
/// display size (via cacheWidth) so scrolling long image lists doesn't
/// re-download or decode oversized bitmaps — the main source of scroll jank.
///
/// Pass the logical [width]/[height] of the box it fills; the decode size is
/// derived from that and the device pixel ratio, so quality is preserved while
/// memory stays low.
class AppCachedImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  /// Logical width used to size the in-memory decode. Defaults to [width].
  final double? decodeWidth;

  const AppCachedImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.decodeWidth,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
    final logicalW = decodeWidth ?? width;
    final memW = (logicalW != null && logicalW > 0)
        ? (logicalW * dpr).round()
        : null;

    Widget image;
    if (url == null || url!.isEmpty) {
      image = _fallback();
    } else {
      image = CachedNetworkImage(
        imageUrl: url!,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: memW,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, __) => _placeholder(),
        errorWidget: (_, __, ___) => _fallback(),
      );
    }

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }

  Widget _placeholder() => Container(
        width: width,
        height: height,
        color: const Color(0xFFE9E9EC),
      );

  Widget _fallback() => Container(
        width: width,
        height: height,
        color: const Color(0xFFE9E9EC),
        child: const Center(
          child: Icon(Icons.image_not_supported_outlined,
              color: Color(0xFFB4B4BC), size: 22),
        ),
      );
}
