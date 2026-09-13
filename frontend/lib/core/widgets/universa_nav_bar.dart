import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';

/// Unified top navigation bar shown on ALL screens.
/// Provides consistent navigation to every page in the app.
class UniversaNavBar extends StatelessWidget {
  final String currentRoute;

  const UniversaNavBar({super.key, required this.currentRoute});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // ── Logo ──
          Text(
            'UNIVERSA',
            style: GoogleFonts.playfairDisplay(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.white,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.electricCyan.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.electricCyan.withValues(alpha: 0.3)),
            ),
            child: Text(
              'v1.0',
              style: AppTypography.monoSmall.copyWith(
                color: AppColors.electricCyan,
                fontSize: 8,
              ),
            ),
          ),

          const SizedBox(width: 24),

          // ── Vertical Divider ──
          Container(width: 1, height: 24, color: AppColors.border),

          const SizedBox(width: 16),

          // ── Nav Tabs ──
          _NavTab(
            icon: Icons.dashboard_rounded,
            label: 'Dashboard',
            isActive: currentRoute == '/',
            onTap: () => context.go('/'),
          ),
          const SizedBox(width: 4),
          _NavTab(
            icon: Icons.hub_rounded,
            label: 'Canvas',
            isActive: currentRoute == '/canvas',
            onTap: () => context.go('/canvas'),
          ),
          const SizedBox(width: 4),
          _NavTab(
            icon: Icons.play_circle_rounded,
            label: 'Studio',
            isActive: currentRoute == '/studio',
            onTap: () => context.go('/studio'),
          ),
          const SizedBox(width: 4),
          _NavTab(
            icon: Icons.search_rounded,
            label: 'Search',
            isActive: currentRoute == '/search',
            onTap: () => context.go('/search'),
          ),
          const SizedBox(width: 4),
          _NavTab(
            icon: Icons.description_rounded,
            label: 'Reports',
            isActive: currentRoute == '/report',
            onTap: () => context.go('/report/CASE-2026-0143'),
          ),

          const Spacer(),

          // ── Right side: status + profile ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.emerald.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.emerald,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'ENCLAVE SECURE',
                  style: AppTypography.monoSmall.copyWith(
                    color: AppColors.emerald,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.surfaceLight,
            child: Icon(Icons.person, color: AppColors.textMuted, size: 16),
          ),
        ],
      ),
    );
  }
}

class _NavTab extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavTab({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_NavTab> createState() => _NavTabState();
}

class _NavTabState extends State<_NavTab> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final isHighlighted = widget.isActive || _hovering;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: widget.isActive
                ? AppColors.electricCyan.withValues(alpha: 0.15)
                : _hovering
                    ? AppColors.surfaceLight
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: widget.isActive
                ? Border.all(color: AppColors.electricCyan.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: isHighlighted ? AppColors.electricCyan : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: AppTypography.labelSmall.copyWith(
                  color: isHighlighted ? AppColors.electricCyan : AppColors.textMuted,
                  fontWeight: widget.isActive ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
