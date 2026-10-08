import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/catalog/menu_model.dart';
import '../providers/rewards/membership_provider.dart';
import '../utils/app_theme.dart';
import 'app_cached_image.dart';
import 'package:food_driver/config/app_constants.dart';

class MenuItemCard extends ConsumerWidget {
  final MenuItem item;
  final VoidCallback onAddTap;
  final VoidCallback? onTap;

  const MenuItemCard({
    super.key,
    required this.item,
    required this.onAddTap,
    this.onTap,
  });

  /// Price line. Members with a HotBite+ price see the regular price struck
  /// through and the member price highlighted; everyone else sees the normal
  /// (discounted) price with any existing % discount slashed.
  Widget _priceRow(bool isMember) {
    final showMember = isMember && item.hasMemberPrice;
    final sym = AppConstants.currencySymbol;
    return Row(
      children: [
        if (showMember) ...[
          // Active member: HotBite+ badge first, then the member price (no slash).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFF5A1F),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.workspace_premium_rounded,
                    size: 15, color: Colors.white),
                SizedBox(width: 3),
                Text('HotBite+',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          const SizedBox(width: 7),
          Text('$sym${item.memberPrice.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: Color(0xFFFF5A1F))),
        ] else ...[
          if (item.discount != null && item.discount! > 0) ...[
            Text('$sym${item.price.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textLight,
                    decoration: TextDecoration.lineThrough)),
            const SizedBox(width: 4),
          ],
          Text('$sym${item.discountedPrice.toStringAsFixed(2)}',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppTheme.priceColor)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMember = ref.watch(isHotBitePlusMemberProvider);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Name, description, price
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.description?.isNotEmpty == true) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.description!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  _priceRow(isMember),
                  // For non-members, tease the HotBite+ price to prompt joining.
                  if (!isMember && item.hasMemberPrice) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.workspace_premium_rounded,
                            size: 12, color: Color(0xFFFF5A1F)),
                        const SizedBox(width: 3),
                        Text(
                          'HotBite+ ${AppConstants.currencySymbol}${item.memberPrice.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFF5A1F),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Square item image with the add button overlaid at its bottom.
            SizedBox(
              width: 80,
              height: 80,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AppCachedImage(
                    url: item.imageUrl?.isNotEmpty == true
                        ? item.imageUrl
                        : null,
                    width: 80,
                    height: 80,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  // Teal circular add button, centred on the image's bottom edge.
                  Positioned(
                    bottom: -14,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: onAddTap,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.add,
                              color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
