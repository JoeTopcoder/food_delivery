/// One candidate product image returned by the web image search
/// (grocery/product-images). [original] is the full-size source image;
/// [thumbnail] is a small preview for the grid.
class ProductImageResult {
  final String thumbnail;
  final String original;
  final String title;
  final String source;

  const ProductImageResult({
    required this.thumbnail,
    required this.original,
    required this.title,
    required this.source,
  });

  factory ProductImageResult.fromJson(Map<String, dynamic> json) =>
      ProductImageResult(
        thumbnail:
            (json['thumbnail'] as String?) ?? (json['original'] as String? ?? ''),
        original: (json['original'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        source: (json['source'] as String?) ?? '',
      );
}
