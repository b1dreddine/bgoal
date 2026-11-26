import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../widgets/info_message.dart';
import '../../widgets/team_crest.dart';
import 'event_icons.dart';
import 'match_logic.dart';

/// One team at a time (switch at the top): formation on a pitch, then substitutes.
class LineupsTab extends StatefulWidget {
  const LineupsTab({super.key, required this.match});

  final FootballMatch match;

  @override
  State<LineupsTab> createState() => _LineupsTabState();
}

class _LineupsTabState extends State<LineupsTab> {
  bool _home = true;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final m = widget.match;
    if (m.lineups.isEmpty) {
      return InfoMessage(
        icon: Icons.groups_outlined,
        text: m.status == MatchStatus.scheduled ? s.lineupsSoon : s.noLineups,
      );
    }

    final team = _home ? m.home : m.away;
    final lineup = m.lineupFor(team.id);
    final rows = lineup == null ? null : pitchRows(lineup);
    final events = m.hasEventData ? m.events : const <MatchEvent>[];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              for (final (isHome, t) in [(true, m.home), (false, m.away)])
                ButtonSegment(
                  value: isHome,
                  icon: TeamCrest(url: t.crestUrl, fallback: t.tla ?? t.displayName, size: 18),
                  label: Text(t.displayName, overflow: TextOverflow.ellipsis),
                ),
            ],
            selected: {_home},
            onSelectionChanged: (v) => setState(() => _home = v.first),
          ),
        ),
        if (lineup == null)
          InfoMessage(icon: Icons.groups_outlined, text: s.noLineups)
        else ...[
          if (lineup.formation != null || lineup.coach != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  if (lineup.formation != null)
                    Text(lineup.formation!, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (lineup.coach != null)
                    Flexible(
                      flex: 4,
                      child: Text(
                        s.coach(lineup.coach!),
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
          if (rows != null)
            _Pitch(rows: rows, events: events)
          else
            for (final p in lineup.starting) _PlayerTile(player: p, marks: playerMarks(events, p)),
          if (lineup.substitutes.isNotEmpty) ...[
            Semantics(
              header: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                child: Text(s.substitutes, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
            for (final p in lineup.substitutes) _PlayerTile(player: p, marks: playerMarks(events, p)),
          ],
        ],
      ],
    );
  }
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({required this.player, required this.marks});

  final LineupPlayer player;
  final PlayerMarks marks;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final spokenMarks = PlayerMarksRow.spoken(s, marks);
    return Semantics(
      container: true,
      label: [s.semPlayer(player.number, player.name), if (spokenMarks.isNotEmpty) spokenMarks].join(', '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                player.number?.toString() ?? '',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(player.name, style: theme.textTheme.bodyLarge)),
            PlayerMarksRow(marks: marks),
          ],
        ),
      ),
    );
  }
}

/// Starting XI on a pitch, goalkeeper at the bottom.
class _Pitch extends StatelessWidget {
  const _Pitch({required this.rows, required this.events});

  final List<List<LineupPlayer>> rows;
  final List<MatchEvent> events;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1B4D2A) : const Color(0xFF2E7D32),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _PitchLines(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
          child: Column(
            children: [
              for (final row in rows.reversed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final p in row) Expanded(child: _PitchPlayer(player: p, marks: playerMarks(events, p))),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PitchPlayer extends StatelessWidget {
  const _PitchPlayer({required this.player, required this.marks});

  final LineupPlayer player;
  final PlayerMarks marks;

  /// "Y. Ziyech" -> "Ziyech": the pitch has room for one word per player.
  static String _shortName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? name : parts.last;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final spokenMarks = PlayerMarksRow.spoken(s, marks);
    return Semantics(
      container: true,
      label: [s.semPlayer(player.number, player.name), if (spokenMarks.isNotEmpty) spokenMarks].join(', '),
      excludeSemantics: true,
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: FittedBox(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Text(
                  player.number?.toString() ?? '',
                  style: theme.textTheme.labelLarge?.copyWith(color: Colors.black87, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _shortName(player.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          if (!marks.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: PlayerMarksRow(marks: marks, color: Colors.white),
            ),
        ],
      ),
    );
  }
}

class _PitchLines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final r = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    canvas.drawRect(r, paint);
    canvas.drawLine(Offset(r.left, r.center.dy), Offset(r.right, r.center.dy), paint);
    canvas.drawCircle(r.center, r.width * 0.12, paint);
    final boxW = r.width * 0.5, boxH = r.height * 0.12;
    canvas.drawRect(Rect.fromLTWH(r.center.dx - boxW / 2, r.top, boxW, boxH), paint);
    canvas.drawRect(Rect.fromLTWH(r.center.dx - boxW / 2, r.bottom - boxH, boxW, boxH), paint);
  }

  @override
  bool shouldRepaint(_PitchLines oldDelegate) => false;
}
