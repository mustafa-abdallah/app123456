# knowledge_app

## الهيكل
```
lib/
  app/           التطبيق، التنقل (الشريط السفلي)، الثيم
  core/          أدوات وعناصر مشتركة
  database/      الجداول + قاعدة البيانات + الترحيلات
  repositories/  الطبقة بين الواجهة والبيانات
  services/      النسخ الاحتياطي، التذكيرات، المرفقات (لاحقًا)
  features/      dashboard / notes / tasks / habits ...
test/            يعكس نفس الهيكل
```

## التشغيل محليًا
```bash
flutter create . --platforms=android
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter run
```

## قاعدة البيانات والترحيل
- الإصدار الحالي: **3** (انظر التعليق فوق `schemaVersion` في `lib/database/database.dart`).
- عند أي تغيير في الجداول: ارفع الرقم، أضف `if (from < N)` في `onUpgrade`، وأضف اختبارًا في
  `test/database/migration_test.dart` يحاكي القاعدة القديمة ويتحقق من بقاء البيانات.

## النسخ الاحتياطي
- من الإعدادات: حفظ في ملف JSON، واستعادة بالدمج أو الاستبدال.
- الصيغة 2 تحمل أعداد الجداول ومجموعًا اختباريًا SHA-256؛ يُفحص الملف قبل أي تغيير.
- الاستعادة معاملة واحدة: إن فشل شيء يُتراجع عن كل شيء.
