import 'package:flutter/material.dart';
import 'package:note_v4/core/app_spacing.dart';
import 'package:note_v4/theme.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.xxl,
            vertical: compact ? AppSpacing.xl : AppSpacing.xxxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: palette.accentContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: palette.accent),
              ),
              SizedBox(height: compact ? AppSpacing.md : AppSpacing.xl),
              Text(
                title,
                textAlign: TextAlign.center,
                style: context.sectionTitle.copyWith(fontSize: 18),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: context.secondaryText.copyWith(height: 1.4),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
