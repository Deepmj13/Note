import 'package:flutter/material.dart';
import 'package:note_v4/core/app_spacing.dart';

Route<T> appPageRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: AppDuration.normal,
    reverseTransitionDuration: AppDuration.quick,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
