import 'package:flutter/material.dart';

class AppSpacing {
  AppSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;
}

class AppRadius {
  AppRadius._();

  static const double small = 12;
  static const double card = 20;
  static const double sheet = 28;
  static const double control = 16;
  static const double fab = 20;
  static const double chip = 20;
}

class AppDuration {
  AppDuration._();

  static const Duration micro = Duration(milliseconds: 100);
  static const Duration quick = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 300);
}

const EdgeInsets kPagePadding = EdgeInsets.symmetric(
  horizontal: AppSpacing.md,
);
