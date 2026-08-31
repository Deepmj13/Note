import 'package:flutter/material.dart';
import 'package:note_v4/core/app_spacing.dart';
import 'package:note_v4/theme.dart';

class SkeletonCard extends StatefulWidget {
  const SkeletonCard({super.key});

  @override
  State<SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.55, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        height: 118,
        decoration: BoxDecoration(
          color: palette.skeletonBase,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bar(
              width: 0.45,
              height: 17,
              color: palette.skeletonHighlight,
            ),
            const SizedBox(height: AppSpacing.md),
            _bar(width: 0.9, height: 13, color: palette.skeletonHighlight),
            const SizedBox(height: AppSpacing.xs),
            _bar(width: 0.7, height: 13, color: palette.skeletonHighlight),
            const Spacer(),
            _bar(width: 0.3, height: 11, color: palette.skeletonHighlight),
          ],
        ),
      ),
    );
  }

  Widget _bar({
    required double width,
    required double height,
    required Color color,
  }) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: width,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}
