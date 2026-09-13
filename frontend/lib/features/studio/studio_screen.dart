import 'package:flutter/material.dart';
import 'package:universa/features/studio/widgets/studio_top_bar.dart';
import 'package:universa/features/studio/widgets/studio_sidebar.dart';
import 'package:universa/features/studio/widgets/studio_feeds_bar.dart';
import 'package:universa/features/studio/widgets/studio_viewport.dart';
import 'package:universa/features/studio/widgets/forensic_inspector.dart';
import 'package:universa/features/studio/widgets/chrono_strip.dart';

/// Linear Studio Pro — forensic video player and evidence review interface.
class StudioScreen extends StatelessWidget {
  const StudioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Studio Sub-Bar ──
        const StudioTopBar(),

        // ── Main Body ──
        Expanded(
          child: Row(
            children: [
              // ── Left Sidebar ──
              const StudioSidebar(),

              // ── Center Content ──
              Expanded(
                child: Column(
                  children: [
                    const StudioFeedsBar(),
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: StudioViewport(),
                      ),
                    ),
                    const ChronoStrip(),
                  ],
                ),
              ),

              // ── Right Inspector Drawer ──
              const ForensicInspector(),
            ],
          ),
        ),
      ],
    );
  }
}
