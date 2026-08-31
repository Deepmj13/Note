import 'package:flutter/material.dart';
import 'package:note_v4/core/app_spacing.dart';

class Entrance extends StatefulWidget {
  const Entrance({
    super.key,
    required this.child,
    this.index = 0,
    this.staggerStep = const Duration(milliseconds: 40),
  });

  final Widget child;
  final int index;
  final Duration staggerStep;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDuration.slow,
  );

  @override
  void initState() {
    super.initState();
    final delay = Duration(
      milliseconds: widget.index * widget.staggerStep.inMilliseconds,
    );
    Future.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}
