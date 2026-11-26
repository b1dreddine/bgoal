import 'package:flutter/material.dart';

/// Centered icon + text (+ optional button) for empty and error states.
///
/// Becomes its own always-scrollable list when it isn't already inside one, so
/// pull-to-refresh keeps working on empty and error screens.
class InfoMessage extends StatelessWidget {
  const InfoMessage({super.key, required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
    if (Scrollable.maybeOf(context) != null) return body;
    return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [body]);
  }
}
