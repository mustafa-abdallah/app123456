import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../repositories/providers.dart';

/// تاريخ آخر نسخة احتياطية محفوظة في ملف (null = لم تُؤخذ بعد).
final lastBackupProvider = StreamProvider.autoDispose<DateTime?>(
    (ref) => ref.watch(settingsRepositoryProvider).watchLastExport());
