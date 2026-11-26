import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/strings.dart';
import 'home_logic.dart';

/// Horizontal day picker: a few days back, today, a week ahead, plus a calendar button.
class DateStrip extends StatefulWidget {
  const DateStrip({super.key, required this.today, required this.selected, required this.onSelected});

  final DateTime today;
  final DateTime selected;
  final ValueChanged<DateTime> onSelected;

  static const daysBack = 3;
  static const daysAhead = 7;

  @override
  State<DateStrip> createState() => _DateStripState();
}

class _DateStripState extends State<DateStrip> {
  final _todayKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Start with "Today" in view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _todayKey.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.3);
    });
  }

  String _label(BuildContext context, int offset, DateTime day) {
    final s = S.of(context);
    return switch (offset) {
      -1 => s.yesterday,
      0 => s.today,
      1 => s.tomorrow,
      _ => DateFormat.MMMEd(Localizations.localeOf(context).toString()).format(day),
    };
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.selected,
      firstDate: dayFrom(widget.today, -365),
      lastDate: dayFrom(widget.today, 365),
      helpText: S.of(context).pickDate,
    );
    if (picked != null) widget.onSelected(DateTime(picked.year, picked.month, picked.day));
  }

  @override
  Widget build(BuildContext context) {
    final offsets = [for (var i = -DateStrip.daysBack; i <= DateStrip.daysAhead; i++) i];
    final selectedInStrip = offsets.any((o) => dayFrom(widget.today, o) == widget.selected);

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                if (!selectedInStrip)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(DateFormat.yMMMd(Localizations.localeOf(context).toString())
                          .format(widget.selected)),
                      selected: true,
                      onSelected: (_) {},
                    ),
                  ),
                for (final o in offsets)
                  Padding(
                    key: o == 0 ? _todayKey : null,
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(_label(context, o, dayFrom(widget.today, o))),
                      selected: dayFrom(widget.today, o) == widget.selected,
                      onSelected: (_) => widget.onSelected(dayFrom(widget.today, o)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: S.of(context).pickDate,
          icon: const Icon(Icons.calendar_month_outlined),
          onPressed: _pickDate,
        ),
      ],
    );
  }
}
