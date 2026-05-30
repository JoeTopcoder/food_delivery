# Responsive Design Patterns Guide

7Dash Flutter App - Comprehensive patterns for making all 125+ screens production-ready across all devices, sizes, and configurations.

Use this guide to systematically fix remaining screens after restaurant_card.dart template is applied.

---

## PATTERN 1: IMPORT RESPONSIVE UTILITY

Add this import at the top of every screen:

```dart
import '../core/utils/responsive.dart';
```

---

## PATTERN 2: REPLACE HARDCODED PADDING

❌ **BEFORE** (Breaks on small screens):
```dart
Padding(
  padding: const EdgeInsets.all(16),
  child: child,
)
```

✅ **AFTER** (Adapts to screen size):
```dart
Padding(
  padding: EdgeInsets.all(Responsive.cardPadding(context)),
  child: child,
)
```

---

## PATTERN 3: FIX HARDCODED CONTAINER HEIGHTS

❌ **BEFORE** (Fixed 220):
```dart
SizedBox(
  height: 220,
  child: MapContainer(),
)
```

✅ **AFTER** (Responsive):
```dart
SizedBox(
  height: Responsive.mapHeight(context),
  child: MapContainer(),
)
```

---

## PATTERN 4: FIX FONT SIZES FOR ANDROID SCALING

❌ **BEFORE** (Ignores system font scaling):
```dart
Text(
  'Title',
  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
)
```

✅ **AFTER** (Respects system font scaling):
```dart
Text(
  'Title',
  style: TextStyle(
    fontSize: Responsive.headingLarge(context),
    fontWeight: FontWeight.bold,
  ),
)
```

---

## PATTERN 5: FIX GRID/LIST LAYOUTS

❌ **BEFORE** (Fixed 2 columns, breaks on tablets):
```dart
GridView.count(
  crossAxisCount: 2,
  children: items,
)
```

✅ **AFTER** (Adapts columns based on screen width):
```dart
GridView.count(
  crossAxisCount: Responsive.gridColumns(context),
  mainAxisSpacing: Responsive.gridSpacing(context),
  crossAxisSpacing: Responsive.gridSpacing(context),
  children: items,
)
```

---

## PATTERN 6: FIX FORM INPUTS (KEYBOARD HANDLING)

❌ **BEFORE** (Keyboard pushes form off-screen):
```dart
Scaffold(
  body: Column(
    children: [
      FormFields(...),
      SubmitButton(),
    ],
  ),
)
```

✅ **AFTER** (Form scrolls above keyboard):
```dart
Scaffold(
  body: SingleChildScrollView(
    child: Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        children: [
          FormFields(...),
          SubmitButton(),
        ],
      ),
    ),
  ),
)
```

---

## PATTERN 7: FIX TEXT OVERFLOW

❌ **BEFORE** (Text can overflow):
```dart
Text('Very long restaurant name that might overflow')
```

✅ **AFTER** (Text wraps or ellipsis):
```dart
Text(
  'Very long restaurant name that might overflow',
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
)
```

For multiline text:
```dart
Flexible(
  child: Text(
    'Very long text',
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  ),
)
```

---

## PATTERN 8: FIX SAFE AREA (Notches, Gesture Navigation)

❌ **BEFORE** (Content hides behind notch):
```dart
Scaffold(
  body: Column(
    children: [...],
  ),
)
```

✅ **AFTER** (Content accounts for notches):
```dart
Scaffold(
  body: SafeArea(
    child: Column(
      children: [...],
    ),
  ),
)
```

Or with custom padding:
```dart
Scaffold(
  body: Padding(
    padding: Responsive.safePadding(context),
    child: Column(
      children: [...],
    ),
  ),
)
```

---

## PATTERN 9: FIX BUTTONS (Don't cut off on small screens)

❌ **BEFORE** (Text might be cut off):
```dart
ElevatedButton(
  onPressed: onPressed,
  child: Text('Very Long Button Text That Might Overflow'),
)
```

✅ **AFTER** (Button adapts to screen):
```dart
SizedBox(
  width: double.infinity,
  height: Responsive.buttonHeight(context),
  child: ElevatedButton(
    onPressed: onPressed,
    child: Text(
      'Very Long Button Text That Might Overflow',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  ),
)
```

---

## PATTERN 10: FIX DIALOGS & BOTTOM SHEETS

❌ **BEFORE** (Dialog too wide on small phones):
```dart
showDialog(
  context: context,
  builder: (_) => AlertDialog(
    title: Text('Confirm'),
    content: Text('Are you sure?'),
  ),
)
```

✅ **AFTER** (Dialog adapts to screen):
```dart
showDialog(
  context: context,
  builder: (_) => Dialog(
    insetAnimationDuration: const Duration(milliseconds: 100),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: Responsive.dialogMaxWidth(context),
      ),
      child: AlertDialog(
        title: Text('Confirm'),
        content: Text('Are you sure?'),
      ),
    ),
  ),
)
```

For bottom sheets with keyboard:
```dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  builder: (_) => Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.of(context).viewInsets.bottom,
    ),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: Responsive.bottomSheetMaxHeight(context),
      ),
      child: SingleChildScrollView(
        child: FormContent(),
      ),
    ),
  ),
)
```

---

## PATTERN 11: FIX HORIZONTAL LAYOUTS (Rows that should wrap)

❌ **BEFORE** (Row overflows on small screens):
```dart
Row(
  children: [
    Icon(Icons.time),
    SizedBox(width: 8),
    Text('30 min delivery'),
    SizedBox(width: 12),
    Icon(Icons.delivery),
    SizedBox(width: 8),
    Text('\$5.00 delivery fee'),
  ],
)
```

✅ **AFTER** (Wraps on small screens):
```dart
Wrap(
  spacing: Responsive.spacing(context) * 0.5,
  runSpacing: Responsive.spacing(context) * 0.25,
  children: [
    Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.time, size: 15),
        SizedBox(width: 4),
        Text('30 min'),
      ],
    ),
    Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.delivery, size: 15),
        SizedBox(width: 4),
        Text('\$5.00'),
      ],
    ),
  ],
)
```

---

## PATTERN 12: FIX IMAGES & ASPECT RATIOS

❌ **BEFORE** (Fixed aspect ratio):
```dart
Container(
  width: 200,
  height: 200,
  child: Image.network(url, fit: BoxFit.cover),
)
```

✅ **AFTER** (Responsive aspect ratio):
```dart
AspectRatio(
  aspectRatio: Responsive.restaurantCardAspectRatio(context),
  child: Image.network(url, fit: BoxFit.cover),
)
```

---

## PATTERN 13: FIX TABS & NAVIGATION

✅ Always use adaptive tab behavior:
```dart
DefaultTabController(
  length: 3,
  child: Scaffold(
    appBar: AppBar(
      bottom: TabBar(
        isScrollable: Responsive.isPhone(context),
        tabs: tabs,
      ),
    ),
    body: TabBarView(children: children),
  ),
)
```

---

## PATTERN 14: FIX SPACING CONSISTENCY

Use these consistently throughout the app:
```dart
final spacing = Responsive.spacing(context);
final padding = Responsive.cardPadding(context);

Column(
  spacing: spacing,
  children: [
    Container(padding: EdgeInsets.all(padding), child: widget1),
    Container(padding: EdgeInsets.all(padding), child: widget2),
  ],
)
```

---

## QUICK CHECKLIST FOR FIXING A SCREEN

When fixing a screen, go through this checklist:

- [ ] Add import: `import '../core/utils/responsive.dart';`
- [ ] Replace all hardcoded padding
- [ ] Replace all hardcoded heights (except Icon sizes)
- [ ] Replace all hardcoded font sizes
- [ ] Wrap text that might overflow
- [ ] Check for text overflow in Row/Flex layouts
- [ ] Check forms for keyboard handling
- [ ] Check for SafeArea
- [ ] Check grid/list layouts
- [ ] Test on multiple screen sizes (320px, 360px, 480px, 600px+)
- [ ] Test with keyboard open
- [ ] Test with system font scaling (1.3x, 1.5x)
- [ ] Test with system display scaling (1.2x)
- [ ] Check for visual consistency
- [ ] Git commit with message: `"fix: make [ScreenName] responsive"`

---

## ADVANCED PATTERN: CONDITIONAL LAYOUTS

For significantly different layouts on tablets:

```dart
if (Responsive.isTablet(context)) {
  return Row(
    children: [
      Expanded(flex: 1, child: LeftPanel()),
      Expanded(flex: 2, child: RightPanel()),
    ],
  );
} else {
  return Column(
    children: [
      TopPanel(),
      BottomPanel(),
    ],
  );
}
```

---

## COMMON MISTAKES TO AVOID

| ❌ Mistake | ✅ Fix |
|-----------|--------|
| Forgetting Flexible around long text | Always wrap long text in Flexible/Expanded |
| Using Container instead of SafeArea | Use SafeArea to handle notches/gestures |
| Fixed widths on buttons | Use `double.infinity` or Expanded |
| No isScrollControlled on form sheets | Always use `isScrollControlled: true` |
| Forgetting viewInsets.bottom | Add keyboard padding to forms |
| No maxLines on text items | Add `maxLines` and `overflow: ellipsis` |
| Fixed spacing (16px everywhere) | Use `Responsive.spacing(context)` |
| Not testing font scaling | Test on 1.3x and 1.5x scales |
| No landscape testing | Rotate and verify layout |
| SingleChildScrollView instead of Expanded | Use Expanded first, scroll for overflow |

---

## Pattern Quick Reference

| Pattern | Key Helper Method |
|---------|-------------------|
| Padding | `Responsive.cardPadding(context)` |
| Heights | `Responsive.mapHeight(context)` |
| Font sizes | `Responsive.headingLarge(context)` |
| Grid columns | `Responsive.gridColumns(context)` |
| Button height | `Responsive.buttonHeight(context)` |
| Dialog width | `Responsive.dialogMaxWidth(context)` |
| Text overflow | `maxLines + TextOverflow.ellipsis` |
| Safe areas | `SafeArea` or `Responsive.safePadding()` |
| Keyboard padding | `MediaQuery.of(context).viewInsets.bottom` |
| Spacing | `Responsive.spacing(context)` |

---

## Resources

- **Responsive Utility**: `lib/core/utils/responsive.dart`
- **Template Widget**: `lib/widgets/restaurant_card.dart`
- **Automation Script**: `fix_responsive.py`
- **Execution Plan**: `RESPONSIVE_DESIGN_PLAN.md`
- **Quick Start**: `README_RESPONSIVE_DESIGN.md`
