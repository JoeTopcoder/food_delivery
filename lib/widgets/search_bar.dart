import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class CustomSearchBar extends StatelessWidget {
  final Function(String) onChanged;
  final String? hintText;

  const CustomSearchBar({
    super.key,
    required this.onChanged,
    this.hintText = 'Search for restaurant or food',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[400]),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              icon: const Icon(Icons.search, color: Colors.white, size: 20),
              onPressed: () {},
              constraints: const BoxConstraints(minHeight: 38, minWidth: 38),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}
