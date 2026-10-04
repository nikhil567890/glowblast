import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class DemoRibbon extends StatelessWidget {
  final String label;

  const DemoRibbon({
    super.key,
    this.label = 'DEMO MODE – SIMULATED DATA',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.demoRibbonBg,
        border: Border(
          bottom: BorderSide(
            color: AppColors.demoRibbonBorder,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 13,
            color: AppColors.demoRibbonText,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.demoRibbonText,
            ),
          ),
        ],
      ),
    );
  }
}
