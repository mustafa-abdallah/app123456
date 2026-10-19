import 'package:flutter/material.dart';

import '../features/dashboard/screens/dashboard_screen.dart';
import '../features/habits/screens/habits_screen.dart';
import '../features/notes/screens/notes_list_screen.dart';
import '../features/tasks/screens/tasks_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 1; // نفتح على الملاحظات في هذه المرحلة

  static const _pages = <Widget>[
    DashboardScreen(),
    NotesListScreen(),
    TasksScreen(),
    HabitsScreen(),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(child: IndexedStack(index: _index, children: _pages)),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'الرئيسية'),
            NavigationDestination(
                icon: Icon(Icons.description_outlined),
                selectedIcon: Icon(Icons.description),
                label: 'الملاحظات'),
            NavigationDestination(
                icon: Icon(Icons.check_circle_outline),
                selectedIcon: Icon(Icons.check_circle),
                label: 'المهام'),
            NavigationDestination(
                icon: Icon(Icons.local_fire_department_outlined),
                selectedIcon: Icon(Icons.local_fire_department),
                label: 'العادات'),
          ],
        ),
      );
}
