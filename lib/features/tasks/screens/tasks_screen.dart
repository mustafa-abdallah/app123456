import 'package:flutter/material.dart';
import '../../../core/widgets/coming_soon.dart';

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const ComingSoon(title: 'المهام', icon: Icons.check_circle_outline);
}
