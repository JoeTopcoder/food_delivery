#!/usr/bin/env python3
"""
Automated Responsive Design Fixer for Flutter Screens

This script systematically applies responsive design patterns to Flutter screens
using find-and-replace patterns based on RESPONSIVE_PATTERNS_GUIDE.

Usage:
    python fix_responsive.py lib/screens/customer/checkout_screen.dart
    python fix_responsive.py lib/screens/customer/ --recursive
"""

import re
import sys
from pathlib import Path

# Patterns: (old_pattern, new_pattern_template, description)
PATTERNS = [
    # Pattern 1: Import responsive utility (must be first)
    (
        r"^(import .*)\n(?!import.*responsive\.dart)",
        r"\1\nimport '../core/utils/responsive.dart';",
        "Add responsive import",
    ),

    # Pattern 2: Replace fixed padding - EdgeInsets.all()
    (
        r"EdgeInsets\.all\(16\)",
        "EdgeInsets.all(Responsive.cardPadding(context))",
        "Replace EdgeInsets.all(16)",
    ),
    (
        r"EdgeInsets\.all\(14\)",
        "EdgeInsets.all(Responsive.cardPadding(context))",
        "Replace EdgeInsets.all(14)",
    ),
    (
        r"EdgeInsets\.all\(12\)",
        "EdgeInsets.all(Responsive.spacing(context))",
        "Replace EdgeInsets.all(12)",
    ),
    (
        r"EdgeInsets\.all\(10\)",
        "EdgeInsets.all(Responsive.spacingSmall(context))",
        "Replace EdgeInsets.all(10)",
    ),
    (
        r"EdgeInsets\.all\(8\)",
        "EdgeInsets.all(Responsive.spacingSmall(context))",
        "Replace EdgeInsets.all(8)",
    ),

    # Pattern 3: Replace symmetric horizontal padding
    (
        r"EdgeInsets\.symmetric\(horizontal:\s*16\)",
        "EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context))",
        "Replace horizontal padding 16",
    ),
    (
        r"EdgeInsets\.symmetric\(horizontal:\s*20\)",
        "EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context))",
        "Replace horizontal padding 20",
    ),
    (
        r"EdgeInsets\.symmetric\(horizontal:\s*24\)",
        "EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context))",
        "Replace horizontal padding 24",
    ),
    (
        r"EdgeInsets\.symmetric\(horizontal:\s*12\)",
        "EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context) * 0.75)",
        "Replace horizontal padding 12",
    ),

    # Pattern 4: Replace font sizes
    (
        r"fontSize:\s*24(?![0-9])",
        "fontSize: Responsive.headingLarge(context)",
        "Replace font size 24",
    ),
    (
        r"fontSize:\s*22(?![0-9])",
        "fontSize: Responsive.headingMedium(context)",
        "Replace font size 22",
    ),
    (
        r"fontSize:\s*20(?![0-9])",
        "fontSize: Responsive.headingMedium(context)",
        "Replace font size 20",
    ),
    (
        r"fontSize:\s*18(?![0-9])",
        "fontSize: Responsive.headingSmall(context)",
        "Replace font size 18",
    ),
    (
        r"fontSize:\s*16(?![0-9])",
        "fontSize: Responsive.headingSmall(context)",
        "Replace font size 16",
    ),
    (
        r"fontSize:\s*14(?![0-9])",
        "fontSize: Responsive.bodyText(context)",
        "Replace font size 14",
    ),
    (
        r"fontSize:\s*13(?![0-9])",
        "fontSize: Responsive.smallText(context)",
        "Replace font size 13",
    ),
    (
        r"fontSize:\s*12(?![0-9])",
        "fontSize: Responsive.smallText(context)",
        "Replace font size 12",
    ),

    # Pattern 5: Replace BorderRadius
    (
        r"BorderRadius\.circular\(14\)",
        "BorderRadius.circular(Responsive.cardRadius(context))",
        "Replace BorderRadius 14",
    ),
    (
        r"BorderRadius\.circular\(12\)",
        "BorderRadius.circular(Responsive.cardRadius(context))",
        "Replace BorderRadius 12",
    ),
    (
        r"BorderRadius\.circular\(8\)",
        "BorderRadius.circular(Responsive.cardRadius(context) - 2)",
        "Replace BorderRadius 8",
    ),
]

def apply_fixes(file_path: str) -> int:
    """Apply responsive fixes to a single file. Returns number of replacements."""
    path = Path(file_path)
    if not path.exists():
        print(f"❌ File not found: {file_path}")
        return 0

    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    original_content = content
    replacements = 0

    for pattern, replacement, description in PATTERNS:
        try:
            new_content, count = re.subn(pattern, replacement, content, flags=re.MULTILINE)
            if count > 0:
                print(f"  ✓ {description}: {count} replacements")
                replacements += count
                content = new_content
        except Exception as e:
            print(f"  ⚠ {description}: {e}")

    if replacements > 0:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"\n✅ {file_path}: {replacements} total replacements")
        return replacements
    else:
        print(f"\n⚠️  {file_path}: No replacements needed")
        return 0

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python fix_responsive.py <file_or_directory>")
        sys.exit(1)

    target = sys.argv[1]
    total = 0

    if Path(target).is_dir():
        for dart_file in Path(target).rglob("*.dart"):
            print(f"\nProcessing: {dart_file}")
            total += apply_fixes(str(dart_file))
        print(f"\n\n🎉 Total replacements across all files: {total}")
    else:
        print(f"Processing: {target}")
        total = apply_fixes(target)
        if total > 0:
            print(f"\n🎉 {total} replacements completed")
