import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mix into any [State] subclass to make every [setState] call automatically
/// no-op when the widget is no longer mounted.
///
/// Prevents: `setState() called after dispose()` and
///           `Looking up a deactivated widget's ancestor is unsafe`
///
/// Usage:
///   `class _MyState extends State<MyWidget> with SafeStateMixin<MyWidget>`
mixin SafeStateMixin<T extends StatefulWidget> on State<T> {
  @override
  void setState(VoidCallback fn) {
    if (mounted) super.setState(fn);
  }
}

/// Same guard for [ConsumerState] (Riverpod).
///
/// Usage:
///   `class _MyState extends ConsumerState<MyWidget> with SafeConsumerStateMixin<MyWidget>`
mixin SafeConsumerStateMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  @override
  void setState(VoidCallback fn) {
    if (mounted) super.setState(fn);
  }
}
