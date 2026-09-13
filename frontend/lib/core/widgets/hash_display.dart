import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/theme/app_typography.dart';

/// A widget for displaying SHA-256 hashes with an option to truncate and copy.
class HashDisplay extends StatelessWidget {
  final String hash;
  final bool compact;

  const HashDisplay({
    super.key,
    required this.hash,
    this.compact = false,
  });

  String get _displayHash {
    if (compact && hash.length > 24) {
      return '${hash.substring(0, 16)}...${hash.substring(hash.length - 8)}';
    }
    return hash;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Text(
              _displayHash,
              style: AppTypography.monoSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.textMuted),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: hash));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Hash copied')),
              );
            },
          ),
        ],
      ),
    );
  }
}
