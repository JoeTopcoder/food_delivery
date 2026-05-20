import 'package:flutter/material.dart';
import '../models/menu_model.dart';
import '../utils/app_theme.dart';
import 'package:food_driver/config/app_constants.dart';

/// Result returned when the user taps "Add Item".
class MenuItemSheetResult {
  final int quantity;
  final List<MenuItemSide> selectedSides;

  /// Map of groupId -> list of chosen OptionChoice
  final Map<String, List<OptionChoice>> selectedOptions;
  final String? specialInstructions;

  const MenuItemSheetResult({
    required this.quantity,
    required this.selectedSides,
    required this.selectedOptions,
    this.specialInstructions,
  });
}

/// Shows a 7krave-style bottom sheet for a menu item with image, description,
/// sides selection, special instructions, quantity picker, and Add Item button.
Future<MenuItemSheetResult?> showMenuItemDetailSheet(
  BuildContext context,
  MenuItem item,
) {
  return showModalBottomSheet<MenuItemSheetResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _MenuItemDetailSheet(item: item),
  );
}

class _MenuItemDetailSheet extends StatefulWidget {
  final MenuItem item;
  const _MenuItemDetailSheet({required this.item});

  @override
  State<_MenuItemDetailSheet> createState() => _MenuItemDetailSheetState();
}

class _MenuItemDetailSheetState extends State<_MenuItemDetailSheet> {
  int _quantity = 1;
  final Map<String, bool> _selectedSides = {};
  // groupId -> set of selected choice IDs
  final Map<String, Set<String>> _selectedChoices = {};
  final TextEditingController _instructionsController = TextEditingController();
  bool _showInstructions = false;

  MenuItem get item => widget.item;

  List<MenuItemSide> get availableSides =>
      item.sides?.where((s) => s.isAvailable).toList() ?? [];

  List<MenuItemSide> get availableDrinks =>
      availableSides.where((s) => s.sideType == 'drink').toList();

  List<MenuItemSide> get availableSideOnly =>
      availableSides.where((s) => s.sideType != 'drink').toList();

  @override
  void initState() {
    super.initState();
    for (final s in availableSides) {
      _selectedSides[s.id] = false;
    }
    for (final group in item.optionGroups) {
      _selectedChoices[group.id] = {};
    }
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    super.dispose();
  }

  List<MenuItemSide> get chosenSides =>
      availableSides.where((s) => _selectedSides[s.id] == true).toList();

  double get sidesTotal => chosenSides.fold(0.0, (sum, s) => sum + s.price);

  Map<String, List<OptionChoice>> get chosenOptions {
    final result = <String, List<OptionChoice>>{};
    for (final group in item.optionGroups) {
      final selectedIds = _selectedChoices[group.id] ?? {};
      if (selectedIds.isNotEmpty) {
        result[group.id] = group.choices
            .where((c) => selectedIds.contains(c.id))
            .toList();
      }
    }
    return result;
  }

  double get optionsTotal => chosenOptions.values
      .expand((choices) => choices)
      .fold(0.0, (sum, c) => sum + c.price);

  double get subtotal =>
      (item.discountedPrice + sidesTotal + optionsTotal) * _quantity;

  bool get allRequiredSelected {
    for (final group in item.optionGroups) {
      if (group.isRequired) {
        final selected = _selectedChoices[group.id] ?? {};
        if (selected.isEmpty) return false;
      }
    }
    return true;
  }

  void _toggleChoice(OptionGroup group, OptionChoice choice) {
    setState(() {
      final selected = _selectedChoices[group.id] ??= {};
      if (group.isSingleSelect) {
        if (selected.contains(choice.id)) {
          if (!group.isRequired) selected.clear();
        } else {
          selected.clear();
          selected.add(choice.id);
        }
      } else {
        if (selected.contains(choice.id)) {
          selected.remove(choice.id);
        } else if (selected.length < group.maxSelections) {
          selected.add(choice.id);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottomPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Item image — use same fallback URL as MenuItemCard
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    child: Image.network(
                      item.imageUrl?.isNotEmpty == true
                          ? item.imageUrl!
                          : 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=500',
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        height: 220,
                        width: double.infinity,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.fastfood_rounded,
                          size: 64,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                  ),

                  // Name + description
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (item.description != null && item.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                      child: Text(
                        item.description!,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),

                  // Price
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Row(
                      children: [
                        if (item.discount != null && item.discount! > 0) ...[
                          Text(
                            '${AppConstants.currencySymbol}${item.price.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          '${AppConstants.currencySymbol}${item.discountedPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.priceColor,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Option Groups (Flavour, Drink, Chicken piece, etc.)
                  ...item.optionGroups.map((group) => _buildOptionGroup(group)),

                  // Sides / options
                  if (availableSideOnly.isNotEmpty) ...[
                    _buildSectionHeader('Add Sides', false),
                    const SizedBox(height: 4),
                    ...availableSideOnly.map(
                      (side) => _buildSelectionRow(
                        name: side.name,
                        price: side.price,
                        showPrice: true,
                        isSelected: _selectedSides[side.id] == true,
                        onTap: () => setState(
                          () => _selectedSides[side.id] =
                              !(_selectedSides[side.id] ?? false),
                        ),
                      ),
                    ),
                  ],

                  // Drinks
                  if (availableDrinks.isNotEmpty) ...[
                    _buildSectionHeader('Drinks', false),
                    const SizedBox(height: 4),
                    ...availableDrinks.map(
                      (side) => _buildSelectionRow(
                        name: side.name,
                        price: side.price,
                        showPrice: true,
                        isSelected: _selectedSides[side.id] == true,
                        onTap: () => setState(
                          () => _selectedSides[side.id] =
                              !(_selectedSides[side.id] ?? false),
                        ),
                      ),
                    ),
                  ],

                  // Special cooking instructions
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: GestureDetector(
                      onTap: () => setState(
                        () => _showInstructions = !_showInstructions,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.edit_note_rounded,
                              size: 20,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Add special cooking instructions',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_showInstructions)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: TextField(
                        controller: _instructionsController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'e.g. No onions, extra sauce...',
                          hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // Bottom bar: quantity + Add Item button
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              12 + MediaQuery.of(context).padding.bottom,
            ),
            child: Row(
              children: [
                // Quantity selector
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppTheme.primaryColor,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: _quantity > 1
                            ? () => setState(() => _quantity--)
                            : null,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Icon(
                            Icons.remove,
                            size: 20,
                            color: _quantity > 1
                                ? AppTheme.primaryColor
                                : Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '$_quantity',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => setState(() => _quantity++),
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Icon(
                            Icons.add,
                            size: 20,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Add Item button
                Expanded(
                  child: ElevatedButton(
                    onPressed: allRequiredSelected
                        ? () {
                            final instructions =
                                _instructionsController.text.trim().isNotEmpty
                                ? _instructionsController.text.trim()
                                : null;
                            Navigator.pop(
                              context,
                              MenuItemSheetResult(
                                quantity: _quantity,
                                selectedSides: chosenSides,
                                selectedOptions: chosenOptions,
                                specialInstructions: instructions,
                              ),
                            );
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      disabledBackgroundColor: Theme.of(context).colorScheme.outlineVariant,
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Subtotal',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                color: Colors.white70,
                              ),
                            ),
                            Text(
                              '${AppConstants.currencySymbol}${subtotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Add Item',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.shopping_cart_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionGroup(OptionGroup group) {
    final availableChoices = group.choices.where((c) => c.isAvailable).toList();
    if (availableChoices.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(group.name, group.isRequired),
        const SizedBox(height: 4),
        ...availableChoices.map((choice) {
          final isSelected =
              _selectedChoices[group.id]?.contains(choice.id) ?? false;
          return _buildSelectionRow(
            name: choice.name,
            price: choice.price,
            showPrice: choice.price > 0,
            isSelected: isSelected,
            onTap: () => _toggleChoice(group, choice),
          );
        }),
      ],
    );
  }

  Widget _buildSectionHeader(String title, bool isRequired) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isRequired ? '(Required)' : '(Optional)',
            style: TextStyle(
              fontSize: 12,
              color: isRequired
                  ? const Color(0xFFB44D4D)
                  : AppTheme.textSecondary,
              fontWeight: isRequired ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionRow({
    required String name,
    required double price,
    required bool showPrice,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Dark square bullet (7krave style)
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: const Color(0xFF333333),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            if (showPrice && price > 0) ...[
              const SizedBox(width: 8),
              Text(
                '+${AppConstants.currencySymbol}${price.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(width: 10),
            // Selection circle
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppTheme.primaryColor : Colors.grey[350]!,
                  width: 2,
                ),
                color: isSelected ? AppTheme.primaryColor : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
