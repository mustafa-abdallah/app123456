import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'database/database.dart';
import 'repositories/providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // تُفتح قاعدة البيانات مرة واحدة، ولا يُعاد إنشاؤها عند كل تشغيل.
  final db = AppDatabase(driftDatabase(name: 'knowledge'));
  runApp(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const KnowledgeApp(),
  ));
}
