import 'package:flutter/material.dart';
import 'package:universa/features/canvas/widgets/canvas_toolbar.dart';
import 'package:universa/features/canvas/widgets/canvas_toolset_bar.dart';
import 'package:universa/features/canvas/widgets/poi_dossier_node.dart';
import 'package:universa/features/canvas/widgets/trajectory_node.dart';
import 'package:universa/features/canvas/widgets/forensic_viewport_node.dart';
import 'package:universa/features/canvas/widgets/admissibility_dock.dart';
import 'package:universa/features/canvas/widgets/canvas_status_bar.dart';

/// Spatial Dossier Canvas — the main investigation workspace.
///
/// A dense, node-graph canvas interface for court-admissible
/// digital forensics and CCTV reconstruction.
class CanvasScreen extends StatelessWidget {
  const CanvasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
          // ── Top Toolbar ──
          const CanvasToolbar(),

          // ── Canvas Toolset Bar ──
          const CanvasToolsetBar(),

          // ── Main Canvas Workspace (3 Nodes) ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // For narrow screens, stack vertically
                  if (constraints.maxWidth < 900) {
                    return SingleChildScrollView(
                      child: Column(
                        children: [
                          const PoiDossierNode(),
                          const SizedBox(height: 12),
                          const TrajectoryNode(),
                          const SizedBox(height: 12),
                          const ForensicViewportNode(),
                          const SizedBox(height: 16),
                          const AdmissibilityDock(),
                          const SizedBox(height: 8),
                        ],
                      ),
                    );
                  }

                  // Desktop layout: 3 columns + bottom dock
                  return Column(
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                          // Left Node: POI Profile Dossier (~25%)
                            Expanded(
                              flex: 25,
                              child: ClipRect(
                                child: SingleChildScrollView(
                                  child: const PoiDossierNode(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Center Node: Multi-Cam Trajectory (~40%)
                            Expanded(
                              flex: 40,
                              child: ClipRect(
                                child: SingleChildScrollView(
                                  child: const TrajectoryNode(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Right Node: Target Forensic Viewport (~35%)
                            Expanded(
                              flex: 35,
                              child: ClipRect(
                                child: SingleChildScrollView(
                                  child: const ForensicViewportNode(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Bottom Admissibility Dock ──
                      const SizedBox(height: 12),
                      const AdmissibilityDock(),
                    ],
                  );
                },
              ),
            ),
          ),

          // ── Bottom Status Bar ──
          const CanvasStatusBar(),
        ],
    );
  }
}
