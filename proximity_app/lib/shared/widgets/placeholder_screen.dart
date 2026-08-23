import 'package:flutter/material.dart';

/// Same role as Baker Ally's placeholder_screen.dart: a real, navigable
/// screen for a tab/route whose actual feature hasn't been built yet, so
/// the router and bottom nav are fully wired and testable before every
/// feature exists. Home/Categories/Cart/Order Again all use this until
/// their real sprints (4, 3, 6, 10) land.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text('$title -- coming soon', style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}
