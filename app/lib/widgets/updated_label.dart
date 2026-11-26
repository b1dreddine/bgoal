import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'match_format.dart';

/// "Updated 18:42", or a highlighted "Offline · last updated 18:42" when showing
/// the on-device copy ([offline]) or old provider data ([stale]).
class UpdatedLabel extends StatelessWidget {
  const UpdatedLabel({super.key, required this.updatedAt, this.offline = false, this.stale = false});

  final DateTime updatedAt;
  final bool offline;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final time = localTime(context, updatedAt);
    final warn = offline || stale;
    final text = offline ? s.offline(time) : s.updatedAt(time);
    return Semantics(
      liveRegion: offline,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: warn ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8) : EdgeInsets.zero,
        decoration: warn
            ? BoxDecoration(color: theme.colorScheme.errorContainer, borderRadius: BorderRadius.circular(8))
            : null,
        child: Row(
          children: [
            if (warn)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Icon(Icons.cloud_off_rounded, size: 18, color: theme.colorScheme.onErrorContainer),
              ),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: warn ? theme.colorScheme.onErrorContainer : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
