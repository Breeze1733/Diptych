import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import 'feed_screen.dart';
import 'profile_screen.dart';
import 'topics_screen.dart';

/// Retain each visited section's scroll position and local state.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final List<Widget?> _pages = [const FeedScreen(), null, null];

  void _selectPage(int index) {
    if (_selectedIndex == index) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _pages[index] ??= switch (index) {
        1 => const TopicsScreen(),
        _ => const ProfileScreen(),
      };
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedIndex != 0) _selectPage(0);
      },
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            for (final page in _pages) page ?? const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.dividerColor)),
          ),
          child: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _selectPage,
            height: 52,
            labelPadding: EdgeInsets.zero,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.auto_stories_outlined),
                selectedIcon: Icon(Icons.auto_stories_rounded),
                label: '日记',
              ),
              NavigationDestination(
                icon: Icon(Icons.forum_outlined),
                selectedIcon: Icon(Icons.forum_rounded),
                label: '话题',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: '我的',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
