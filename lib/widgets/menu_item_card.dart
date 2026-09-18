import 'package:flutter/material.dart';
import '../models/menu_model.dart';
import '../utils/app_theme.dart';
import 'app_cached_image.dart';
import 'package:food_driver/config/app_constants.dart';

class MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final VoidCallback onAddTap;
  final VoidCallback? onTap;

  const MenuItemCard({
    super.key,
    required this.item,
    required this.onAddTap,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
            // Square item image (cached + decoded at thumbnail size)
            AppCachedImage(
              url: item.imageUrl?.isNotEmpty == true ? item.imageUrl : null,
              width: 80,
              height: 80,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(width: 14),
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
                  Row(
                    children: [
                      if (item.discount != null && item.discount! > 0) ...[
                        Text(
                          '${AppConstants.currencySymbol}${item.price.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textLight,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        '${AppConstants.currencySymbol}${item.discountedPrice.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppTheme.priceColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Teal circular add button
            GestureDetector(
              onTap: onAddTap,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
