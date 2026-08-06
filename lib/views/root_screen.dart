import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import '../viewmodels/combinations_viewmodel.dart';
import '../viewmodels/looks_viewmodel.dart';
import 'closet/closet_screen.dart';
import 'combinations/combinations_screen.dart';
import 'looks/looks_screen.dart';
import 'match/match_screen.dart';

/// The four sections, in the order of the work: see what you own, judge it,
/// browse what has been judged, keep what you liked.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _index = 0;

  static const _tabs = [
    ClosetScreen(),
    MatchScreen(),
    CombinationsScreen(),
    LooksScreen(),
  ];

  void _onTap(int index) {
    if (index == _index) return;
    setState(() => _index = index);

    // Both of these read derived state that Match writes, so they refresh on
    // arrival rather than holding a stale view from before the last scoring run.
    if (index == 2) context.read<CombinationsViewModel>().load();
    if (index == 3) context.read<LooksViewModel>().load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack so scroll position and in-progress selections survive tab
      // switches. Losing a half-built selection because the user glanced at
      // another tab would be its own bug.
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Ink0.raised,
          border: Border(top: BorderSide(color: Bone.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: Colors.transparent,
              indicatorColor: Accent.brass.withValues(alpha: 0.16),
              surfaceTintColor: Colors.transparent,
              height: 64,
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.4,
                  fontWeight:
                      states.contains(WidgetState.selected)
                          ? FontWeight.w600
                          : FontWeight.w400,
                  color:
                      states.contains(WidgetState.selected)
                          ? Accent.brass
                          : Bone.muted,
                ),
              ),
              iconTheme: WidgetStateProperty.resolveWith(
                (states) => IconThemeData(
                  size: 22,
                  color:
                      states.contains(WidgetState.selected)
                          ? Accent.brass
                          : Bone.muted,
                ),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _onTap,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.checkroom_outlined),
                  selectedIcon: Icon(Icons.checkroom),
                  label: 'Closet',
                ),
                NavigationDestination(
                  icon: Icon(Icons.style_outlined),
                  selectedIcon: Icon(Icons.style),
                  label: 'Match',
                ),
                NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view),
                  label: 'Combos',
                ),
                NavigationDestination(
                  icon: Icon(Icons.collections_bookmark_outlined),
                  selectedIcon: Icon(Icons.collections_bookmark),
                  label: 'Looks',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
