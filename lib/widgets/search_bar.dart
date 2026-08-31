import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class CustomSearchBar extends StatefulWidget {
  final Function(String) onChanged;
  final String? hintText;

  const CustomSearchBar({
    super.key,
    required this.onChanged,
    this.hintText = 'Search for restaurant or food',
  });

  @override
  State<CustomSearchBar> createState() => _CustomSearchBarState();
}

class _CustomSearchBarState extends State<CustomSearchBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isFocused
              ? AppTheme.primaryColor.withValues(alpha: 0.55)
              : colors.outlineVariant.withValues(alpha: 0.6),
          width: _isFocused ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: _isFocused ? 14 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 6),
          Container(
            width: 34,
            height: 34,
            margin: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(
                alpha: _isFocused ? 0.16 : 0.10,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.search_rounded,
              color: AppTheme.primaryColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: widget.onChanged,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: colors.onSurface,
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (_hasText)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: _clear,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 14),
        ],
      ),
    );
  }
}
