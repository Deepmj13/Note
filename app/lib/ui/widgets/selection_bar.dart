import 'package:flutter/material.dart';
import 'package:note_v4/core/app_spacing.dart';
import 'package:note_v4/theme.dart';

class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.count,
    required this.onClose,
    required this.onToggleFavorite,
    required this.onPin,
    required this.onMove,
    required this.onDelete,
  });

  final int count;
  final VoidCallback onClose;
  final VoidCallback onToggleFavorite;
  final VoidCallback onPin;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      height: 56,
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: palette.elevatedSurface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: palette.divider),
      ),
      child: Row(
        children: [
          _BarButton(
            icon: Icons.close,
            tooltip: 'Close selection',
            onTap: onClose,
          ),
          Expanded(
            child: Text(
              '$count selected',
              style: context.bodyText.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          _BarButton(
            icon: Icons.star_border,
            tooltip: 'Add to favorites',
            onTap: onToggleFavorite,
          ),
          _BarButton(
            icon: Icons.push_pin_outlined,
            tooltip: 'Pin',
            onTap: onPin,
          ),
          _BarButton(
            icon: Icons.drive_file_move_outline,
            tooltip: 'Move',
            onTap: onMove,
          ),
          _BarButton(
            icon: Icons.delete_outline,
            tooltip: 'Delete',
            color: palette.danger,
            onTap: onDelete,
          ),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 22),
      color: color,
      tooltip: tooltip,
      onPressed: onTap,
    );
  }
}
