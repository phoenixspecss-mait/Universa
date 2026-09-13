import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:universa/core/theme/app_colors.dart';
import 'package:universa/core/widgets/universa_nav_bar.dart';
import 'package:universa/features/canvas/canvas_screen.dart';
import 'package:universa/features/studio/studio_screen.dart';
import 'package:universa/features/dashboard/dashboard_screen.dart';
import 'package:universa/features/search/search_screen.dart';
import 'package:universa/features/report/report_screen.dart';

/// GoRouter configuration for UNIVERSA.
/// All screens share the same UniversaNavBar at the top.
final appRouter = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) {
          return _AppShellWithNav(
            currentRoute: state.uri.path,
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: '/',
            builder: (ctx, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/canvas',
            builder: (ctx, state) => const CanvasScreen(),
          ),
          GoRoute(
            path: '/studio',
            builder: (ctx, state) => const StudioScreen(),
          ),
          GoRoute(
            path: '/search',
            builder: (ctx, state) => const SearchScreen(),
          ),
          GoRoute(
            path: '/search/:caseId',
            builder: (ctx, state) => SearchScreen(caseId: state.pathParameters['caseId']),
          ),
          GoRoute(
            path: '/report/:caseId',
            builder: (ctx, state) => ReportScreen(caseId: state.pathParameters['caseId']!),
          ),
        ],
      ),
    ],
  );
});

/// Shell that wraps every screen with the unified nav bar.
class _AppShellWithNav extends StatelessWidget {
  final String currentRoute;
  final Widget child;

  const _AppShellWithNav({required this.currentRoute, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          UniversaNavBar(currentRoute: _normalizeRoute(currentRoute)),
          Expanded(child: child),
        ],
      ),
    );
  }

  /// Normalize route for active tab matching
  String _normalizeRoute(String route) {
    if (route.startsWith('/report')) return '/report';
    if (route.startsWith('/search')) return '/search';
    return route;
  }
}
