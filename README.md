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
