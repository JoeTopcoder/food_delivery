import 'package:flutter/material.dart';

/// Shown when a customer tries to add a grocery item from a different store
/// than the one already in their cart. One order = one grocery store, so we
/// offer to start a fresh cart. Returns true if they chose to replace.
Future<bool?> confirmNewGroceryCart(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Start a new cart?'),
      content: const Text(
        'Your grocery cart has items from another store. You can only order '
        'from one grocery store at a time. Clear it and start with this item?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Keep cart'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Start new cart'),
        ),
      ],
    ),
  );
}
