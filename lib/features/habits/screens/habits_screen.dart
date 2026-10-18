import 'package:flutter/material.dart';
import '../../../core/widgets/coming_soon.dart';

class HabitsScreen extends StatelessWidget {
  const HabitsScreen({super.key});
  @override
  Widget build(BuildContext context) => const ComingSoon(
      title: 'العادات', icon: Icons.local_fire_department_outlined);
}
