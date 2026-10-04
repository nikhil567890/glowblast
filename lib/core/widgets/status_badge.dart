import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class StatusBadge extends StatelessWidget {
  final String label;
  final Color? color;
  final Color? textColor;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.label,
    this.color,
    this.textColor,
    this.icon,
  });

  factory StatusBadge.vip() {
    return const StatusBadge(
      label: 'VIP',
      color: Color(0xFFFBF4E2),
      textColor: Color(0xFF8C6D23),
      icon: Icons.star_rounded,
    );
  }

  factory StatusBadge.inactive() {
    return const StatusBadge(
      label: 'Inactive',
      color: Color(0xFFFEECEB),
      textColor: Color(0xFFC53030),
      icon: Icons.history_toggle_off_rounded,
    );
  }

  factory StatusBadge.regular() {
    return const StatusBadge(
      label: 'Regular',
      color: Color(0xFFE8F5EE),
      textColor: Color(0xFF2D6A4F),
      icon: Icons.check_circle_outline_rounded,
    );
  }

  factory StatusBadge.optedOut() {
    return const StatusBadge(
      label: 'Opted-Out',
      color: Color(0xFFEEEEEE),
      textColor: Color(0xFF616161),
      icon: Icons.block_rounded,
    );
  }

  factory StatusBadge.birthday() {
    return const StatusBadge(
      label: 'Birthday',
      color: Color(0xFFFCE4EC),
      textColor: Color(0xFFC2185B),
      icon: Icons.cake_outlined,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppColors.primarySageContainer;
    final fg = textColor ?? AppColors.primarySageDark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
