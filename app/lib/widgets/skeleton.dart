import 'package:flutter/material.dart';

/// Placeholder shapes that gently pulse while content loads, shaped like what's
/// coming so the screen doesn't jump when it arrives. Still when the system asks
/// for reduced motion.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child});

  final Widget child;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: FadeTransition(
          opacity: Tween(begin: 0.45, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
          child: widget.child,
        ),
      );
}

/// One grey rounded block.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

/// A list of match-card shapes, for the home and team screens while they load.
class MatchListSkeleton extends StatelessWidget {
  const MatchListSkeleton({super.key, this.cards = 6});

  final int cards;

  @override
  Widget build(BuildContext context) {
    Widget team(double nameWidth) => Row(
          children: [
            const SkeletonBox(width: 22, height: 22, radius: 11),
            const SizedBox(width: 10),
            SkeletonBox(width: nameWidth, height: 12),
          ],
        );

    return Skeleton(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 16),
        children: [
          for (var i = 0; i < cards; i++) ...[
            if (i % 3 == 0)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Row(children: [SkeletonBox(width: 20, height: 20, radius: 10), SizedBox(width: 10), SkeletonBox(width: 120, height: 12)]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    children: [
                      const SkeletonBox(width: 32, height: 12),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [team(110.0 + (i % 3) * 18), const SizedBox(height: 10), team(90.0 + (i % 2) * 30)],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
