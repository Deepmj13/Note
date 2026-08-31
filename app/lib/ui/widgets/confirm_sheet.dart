import 'package:flutter/material.dart';
import 'package:note_v4/core/app_spacing.dart';
import 'package:note_v4/theme.dart';

Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  IconData icon = Icons.warning_amber_rounded,
  Color? color,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    builder: (context) {
      final palette = context.palette;
      final danger = color ?? palette.danger;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: danger.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: danger, size: 28),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(title, style: context.sectionTitle),
              const SizedBox(height: AppSpacing.xs),
              Text(
                message,
                style: context.secondaryText.copyWith(height: 1.4),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: danger,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(confirmLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return result ?? false;
}
