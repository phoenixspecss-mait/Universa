import 'package:flutter/material.dart';
import 'package:universa/core/theme/app_colors.dart';

/// Sidebar for the Studio screen
class StudioSidebar extends StatelessWidget {
  const StudioSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      padding: const EdgeInsets.only(top: 8),
      decoration: const BoxDecoration(
        color: AppColors.canvasBlack,
        border: Border(
          right: BorderSide(color: AppColors.border),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          _buildIcon(Icons.grid_view, false),
          _buildIcon(Icons.search, true),
          _buildIcon(Icons.edit_note, false),
          _buildIcon(Icons.analytics_outlined, false),
          _buildIcon(Icons.check_circle_outline, false),
          const Spacer(),
          _buildIcon(Icons.settings, false),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildIcon(IconData icon, bool isSelected) {
    return Container(
      width: 40,
      height: 40,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.electricCyan.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Icon(
          icon,
          color: isSelected ? AppColors.electricCyan : AppColors.textMuted,
          size: 20,
        ),
      ),
    );
  }
}
