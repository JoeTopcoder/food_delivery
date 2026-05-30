import 'package:flutter/material.dart';

/// Responsive design utilities for the 7Dash app.
/// Provides breakpoints, spacing, and adaptive values across all device sizes.
class Responsive {
  // ─── Screen Size Getters ─────────────────────────────────────────────────

  static double width(BuildContext context) => MediaQuery.sizeOf(context).width;

  static double height(BuildContext context) =>
      MediaQuery.sizeOf(context).height;

  static double topPadding(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).top;

  static double bottomPadding(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).bottom;

  static double leftPadding(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).left;

  static double rightPadding(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).right;

  static bool isLandscape(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  static TextScaler textScaler(BuildContext context) =>
      MediaQuery.textScalerOf(context);

  // ─── Breakpoints ────────────────────────────────────────────────────────

  /// Phones: width < 360dp (e.g., older Android, small iPhones)
  static bool isSmallPhone(BuildContext context) => width(context) < 360;

  /// Standard phones: 360dp ≤ width < 480dp (most Android phones)
  static bool isStandardPhone(BuildContext context) {
    final w = width(context);
    return w >= 360 && w < 480;
  }

  /// Large phones: 480dp ≤ width < 600dp (Plus-sized phones)
  static bool isLargePhone(BuildContext context) {
    final w = width(context);
    return w >= 480 && w < 600;
  }

  /// Phone category: any width < 600dp
  static bool isPhone(BuildContext context) => width(context) < 600;

  /// Tablet/Foldable: width ≥ 600dp
  static bool isTablet(BuildContext context) => width(context) >= 600;

  /// Large tablet/desktop: width ≥ 900dp
  static bool isLargeTablet(BuildContext context) => width(context) >= 900;

  // ─── Adaptive Spacing ───────────────────────────────────────────────────

  /// Horizontal padding for screens (left/right)
  static double horizontalPadding(BuildContext context) {
    final w = width(context);
    if (w < 360) return 12;
    if (w < 480) return 14;
    if (w < 600) return 16;
    if (w < 900) return 24;
    return 32;
  }

  /// Vertical padding for screens (top/bottom)
  static double verticalPadding(BuildContext context) {
    final w = width(context);
    if (w < 360) return 10;
    if (w < 480) return 12;
    if (w < 600) return 14;
    if (w < 900) return 18;
    return 24;
  }

  /// General spacing between elements (standard is 16)
  static double spacing(BuildContext context) {
    final w = width(context);
    if (w < 360) return 8;
    if (w < 480) return 10;
    if (w < 600) return 12;
    if (w < 900) return 16;
    return 20;
  }

  /// Small spacing (1/2 of spacing)
  static double spacingSmall(BuildContext context) => spacing(context) / 2;

  /// Large spacing (2x of spacing)
  static double spacingLarge(BuildContext context) => spacing(context) * 1.5;

  /// Extra large spacing (3x of spacing)
  static double spacingXL(BuildContext context) => spacing(context) * 2;

  // ─── Adaptive Sizes ─────────────────────────────────────────────────────

  /// Card radius
  static double cardRadius(BuildContext context) {
    final w = width(context);
    if (w < 360) return 8;
    if (w < 600) return 10;
    return 12;
  }

  /// Button height
  static double buttonHeight(BuildContext context) {
    final w = width(context);
    if (w < 360) return 44;
    if (w < 600) return 48;
    return 52;
  }

  /// Button padding
  static EdgeInsets buttonPadding(BuildContext context) {
    final h = horizontalPadding(context);
    final v = spacing(context) * 0.75;
    return EdgeInsets.symmetric(horizontal: h, vertical: v);
  }

  /// Card padding
  static double cardPadding(BuildContext context) {
    final w = width(context);
    if (w < 360) return 12;
    if (w < 480) return 14;
    if (w < 600) return 16;
    return 20;
  }

  /// App bar height (besides status bar)
  static double appBarHeight(BuildContext context) {
    final w = width(context);
    if (w < 360) return 56;
    if (w < 600) return 56;
    return 60;
  }

  // ─── Grid & List Layouts ───────────────────────────────────────────────

  /// Grid columns for restaurant/product listings
  static int gridColumns(BuildContext context) {
    final w = width(context);
    if (w < 360) return 1;
    if (w < 480) return 2;
    if (w < 600) return 2;
    if (w < 900) return 3;
    return 4;
  }

  /// Grid spacing
  static double gridSpacing(BuildContext context) => spacing(context);

  /// Grid item width (for responsive grid)
  static double gridItemWidth(BuildContext context) {
    final w = width(context) - horizontalPadding(context) * 2;
    final cols = gridColumns(context);
    final spacing = gridSpacing(context) * (cols - 1);
    return (w - spacing) / cols;
  }

  // ─── Card Aspect Ratios ─────────────────────────────────────────────────

  /// Restaurant card aspect ratio
  static double restaurantCardAspectRatio(BuildContext context) {
    final w = width(context);
    if (w < 360) return 0.56;
    if (w < 480) return 0.60;
    if (w < 600) return 0.64;
    if (w < 900) return 0.72;
    return 0.80;
  }

  /// Product/menu item card aspect ratio
  static double productCardAspectRatio(BuildContext context) {
    final w = width(context);
    if (w < 360) return 0.52;
    if (w < 480) return 0.58;
    if (w < 600) return 0.62;
    if (w < 900) return 0.70;
    return 0.78;
  }

  /// Order card aspect ratio (horizontal)
  static double orderCardAspectRatio(BuildContext context) {
    final w = width(context);
    if (w < 360) return 2.2;
    if (w < 480) return 2.4;
    if (w < 600) return 2.6;
    return 3.0;
  }

  // ─── Font Sizes ─────────────────────────────────────────────────────────

  /// Large heading font size
  static double headingLarge(BuildContext context) {
    final w = width(context);
    if (w < 360) return 20;
    if (w < 600) return 24;
    return 28;
  }

  /// Medium heading font size
  static double headingMedium(BuildContext context) {
    final w = width(context);
    if (w < 360) return 16;
    if (w < 600) return 18;
    return 22;
  }

  /// Small heading font size
  static double headingSmall(BuildContext context) {
    final w = width(context);
    if (w < 360) return 14;
    if (w < 600) return 16;
    return 18;
  }

  /// Body text font size
  static double bodyText(BuildContext context) {
    final w = width(context);
    if (w < 360) return 13;
    if (w < 600) return 14;
    return 15;
  }

  /// Small text font size (captions, labels)
  static double smallText(BuildContext context) {
    final w = width(context);
    if (w < 360) return 11;
    if (w < 600) return 12;
    return 13;
  }

  // ─── Keyboard & Input ───────────────────────────────────────────────────

  /// Input field height
  static double inputHeight(BuildContext context) {
    final w = width(context);
    if (w < 360) return 48;
    if (w < 600) return 52;
    return 56;
  }

  /// Input field padding
  static EdgeInsets inputPadding(BuildContext context) {
    final h = spacing(context);
    final v = spacing(context) * 0.5;
    return EdgeInsets.symmetric(horizontal: h, vertical: v);
  }

  // ─── Safe Area Aware Layouts ───────────────────────────────────────────

  /// Safe horizontal padding (accounts for notch/gesture area)
  static EdgeInsets safePadding(BuildContext context) {
    return EdgeInsets.only(
      left: leftPadding(context) + horizontalPadding(context),
      right: rightPadding(context) + horizontalPadding(context),
      top: topPadding(context) + verticalPadding(context),
      bottom: bottomPadding(context) + verticalPadding(context),
    );
  }

  /// Safe horizontal padding only (left/right)
  static EdgeInsets safeHorizontalPadding(BuildContext context) {
    return EdgeInsets.only(
      left: leftPadding(context) + horizontalPadding(context),
      right: rightPadding(context) + horizontalPadding(context),
    );
  }

  /// Safe vertical padding only (top/bottom)
  static EdgeInsets safeVerticalPadding(BuildContext context) {
    return EdgeInsets.only(
      top: topPadding(context) + verticalPadding(context),
      bottom: bottomPadding(context) + verticalPadding(context),
    );
  }

  // ─── List & Form Layouts ───────────────────────────────────────────────

  /// Max width for centered content (forms, dialogs) on tablets
  static double maxCenteredWidth(BuildContext context) {
    final w = width(context);
    if (w < 600) return w;
    if (w < 900) return 600;
    return 800;
  }

  /// List item height
  static double listItemHeight(BuildContext context) {
    final w = width(context);
    if (w < 360) return 56;
    if (w < 600) return 60;
    return 64;
  }

  // ─── Dialog & Bottom Sheet ──────────────────────────────────────────────

  /// Dialog max width
  static double dialogMaxWidth(BuildContext context) {
    final w = width(context);
    if (w < 600) return w * 0.9;
    if (w < 900) return 500;
    return 600;
  }

  /// Bottom sheet max height (should not cover entire screen)
  static double bottomSheetMaxHeight(BuildContext context) {
    final h = height(context);
    final w = width(context);
    // On small screens, allow more height; on tablets, cap it
    if (w < 600) return h * 0.85;
    return h * 0.75;
  }

  // ─── Image Sizes ────────────────────────────────────────────────────────

  /// Restaurant/store avatar size
  static double avatarLarge(BuildContext context) {
    final w = width(context);
    if (w < 360) return 56;
    if (w < 600) return 64;
    return 72;
  }

  /// User/driver profile picture
  static double avatarMedium(BuildContext context) {
    final w = width(context);
    if (w < 360) return 40;
    if (w < 600) return 48;
    return 56;
  }

  /// Small icon avatar
  static double avatarSmall(BuildContext context) {
    final w = width(context);
    if (w < 360) return 32;
    if (w < 600) return 36;
    return 40;
  }

  /// Cart item image size (for shopping cart items)
  static double cartItemImageSize(BuildContext context) {
    final w = width(context);
    if (w < 360) return 70;
    if (w < 600) return 80;
    return 90;
  }

  // ─── Hero Image Sizes ───────────────────────────────────────────────────

  /// Hero image height (e.g., restaurant header)
  static double heroImageHeight(BuildContext context) {
    final w = width(context);
    if (w < 360) return 200;
    if (w < 480) return 220;
    if (w < 600) return 240;
    if (w < 900) return 280;
    return 320;
  }

  /// Home screen banner height
  static double bannerHeight(BuildContext context) {
    final w = width(context);
    if (w < 360) return 180;
    if (w < 480) return 200;
    if (w < 600) return 220;
    if (w < 900) return 260;
    return 300;
  }

  // ─── Bottom Navigation ──────────────────────────────────────────────────

  /// Bottom navigation bar height
  static double bottomNavHeight(BuildContext context) {
    final w = width(context);
    if (w < 360) return 56;
    if (w < 600) return 60;
    return 64;
  }

  // ─── Map/Location Screens ───────────────────────────────────────────────

  /// Map container height
  static double mapHeight(BuildContext context) {
    final h = height(context);
    final w = width(context);
    if (w < 600) {
      // On phones, map takes 50% of screen
      return h * 0.5;
    }
    // On tablets, map takes 60% of screen
    return h * 0.6;
  }

  /// Location search card height (overlay on map)
  static double locationSearchCardHeight(BuildContext context) {
    final w = width(context);
    if (w < 360) return 200;
    if (w < 600) return 240;
    return 280;
  }

  // ─── Fixed Bottom Button Padding ────────────────────────────────────────

  /// Bottom padding for scrollable content with fixed button (e.g., checkout)
  static double bottomPaddingForFixedButton(BuildContext context) {
    final w = width(context);
    // Account for button height + safe area + extra padding
    if (w < 360) return 150;
    if (w < 600) return 170;
    return 200;
  }
}
