import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final greeting = DateTime.now().hour < 12 ? 'صباح الخير' : 'مساء الخير';
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(greeting, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 4),
        Text('لوحة التحكم',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const Expanded(
            child: Center(child: Text('تُضاف أقسام اللوحة في مرحلة لاحقة'))),
      ]),
    );
  }
}
