import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config.dart';

/// Team crest or competition emblem. Providers serve PNG or SVG; falls back to the
/// team's initials when there is no image or it fails to load. Decorative only, so
/// it's hidden from screen readers (the card announces the team name).
class TeamCrest extends StatelessWidget {
  const TeamCrest({super.key, required this.url, required this.fallback, this.size = 24});

  final String? url;
  final String fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = _Initials(text: fallback, size: size);
    final u = url;
    Widget image;
    if (u == null || u.isEmpty || !AppConfig.showCrests) {
      image = placeholder;
    } else if (u.toLowerCase().endsWith('.svg')) {
      image = SvgPicture.network(u, width: size, height: size, placeholderBuilder: (_) => placeholder);
    } else {
      image = CachedNetworkImage(
        imageUrl: u,
        width: size,
        height: size,
        fit: BoxFit.contain,
        fadeInDuration: const Duration(milliseconds: 120),
        // Decode at display size to keep memory low in long lists.
        memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
      );
    }
    return ExcludeSemantics(child: SizedBox.square(dimension: size, child: image));
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.text, required this.size});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final letters = text.isEmpty ? '?' : text.substring(0, text.length < 3 ? text.length : 3).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, shape: BoxShape.circle),
      child: FittedBox(
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Text(letters, style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
