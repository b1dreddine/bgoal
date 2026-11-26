import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/strings.dart';
import 'team_picker.dart';

/// Find and follow teams (search icon on the home screen, "Teams you follow" in Settings).
class TeamsScreen extends StatelessWidget {
  const TeamsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(S.of(context).teams)),
        body: TeamPicker(onOpen: (team) => context.push('/team/${team.id}', extra: team)),
      );
}
