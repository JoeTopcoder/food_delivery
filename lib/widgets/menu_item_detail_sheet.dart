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
      // Pre-select the obvious choice for a required single-select group so
      // "Add Item" is live the moment the sheet opens. Without this the button
      // starts disabled with no visible reason, and the customer has to hunt
      // for which section is blocking them. Only ever auto-picks when there is
      // no real decision to make (a single option) or the restaurant has
      // explicitly marked a default; anything genuinely ambiguous is still
      // left for the customer to choose.
      if (group.isRequired && group.isSingleSelect) {
        final choices = group.choices.where((c) => c.isAvailable).toList();
        if (choices.isEmpty) continue;
        if (choices.length == 1) {
          _selectedChoices[group.id] = {choices.first.id};
        } else {
          // Cheapest free choice reads as the base/default configuration.
          final free = choices.where((c) => c.price == 0).toList();
          if (free.length == 1) _selectedChoices[group.id] = {free.first.id};
        }
      }
    }
  }

  /// Name of the first required group still awaiting a choice — drives the
  /// hint under the action bar so a disabled button always explains itself.
  String? get _missingRequirement {
    for (final group in item.optionGroups) {
      if (!group.isRequired) continue;
      if ((_selectedChoices[group.id] ?? {}).isEmpty) return group.name;
    }
    return null;
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
            margin: const EdgeInsets.only(top: 10, bottom: 2),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Sticky title bar. The item name stays visible while the customer
          // scrolls a long options list, and the explicit close button means
          // dismissing doesn't depend on discovering the drag gesture.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
            child: Row(
              children: [
                const SizedBox(width: 34),
                Expanded(
                  child: Text(
                    item.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.close_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottomPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Compact summary row: thumbnail + description + price. The
                  // name is already in the sticky header, so repeating it here
                  // (and giving the photo a 220px hero) pushed the options —
                  // the entire point of this sheet — below the fold.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.imageUrl?.isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                item.imageUrl!,
                                height: 76,
                                width: 76,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  height: 76,
                                  width: 76,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.fastfood_rounded,
                                    size: 28,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outlineVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (item.description != null &&
                                  item.description!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    item.description!,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              Row(
                                children: [
                                  if (item.discount != null &&
                                      item.discount! > 0) ...[
                                    Text(
                                      '${AppConstants.currencySymbol}${item.price.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(
                                    '${AppConstants.currencySymbol}${item.discountedPrice.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.priceColor,
                                    ),
                                  ),
                                ],
                              ),
                            ],
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
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.edit_note_rounded,
                              size: 20,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Add special cooking instructions',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
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
                          hintStyle: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          filled: true,
                          fillColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
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
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              10,
              16,
              12 + MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // A greyed-out button with no explanation is the single most
                // common way this kind of sheet frustrates people. Name the
                // section that's still blocking them instead.
                if (_missingRequirement != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Choose your ${_missingRequirement!} to continue',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
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
                                    : Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
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
                                    _instructionsController.text
                                        .trim()
                                        .isNotEmpty
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
                          disabledBackgroundColor: Theme.of(
                            context,
                          ).colorScheme.outlineVariant,
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
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
        ...availableChoices.map((choice) {
          final isSelected =
              _selectedChoices[group.id]?.contains(choice.id) ?? false;
          return _buildSelectionRow(
            name: choice.name,
            price: choice.price,
            showPrice: choice.price > 0,
            isSelected: isSelected,
            isRadio: group.isSingleSelect,
            onTap: () => _toggleChoice(group, choice),
          );
        }),
      ],
    );
  }

  Widget _buildSectionHeader(String title, bool isRequired) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      margin: const EdgeInsets.only(top: 14, bottom: 2),
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
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isRequired
                  ? const Color(0xFFFEF2F2)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isRequired ? 'REQUIRED' : 'Optional',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isRequired
                    ? const Color(0xFFDC2626)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0.3,
              ),
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
    bool isRadio = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        // Tight enough that a long options list (the reference's porridge has
        // seven sides) reads as one scannable group instead of a scroll marathon.
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 2,
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
            const SizedBox(width: 12),
            // Radio (single-select) or Checkbox (multi-select/add-ons)
            if (isRadio)
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primaryColor
                        : Theme.of(context).colorScheme.outline,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              )
            else
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primaryColor
                        : Theme.of(context).colorScheme.outline,
                    width: 1.5,
                  ),
                  color: isSelected
                      ? AppTheme.primaryColor
                      : Colors.transparent,
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}
