import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// دالة عامة ليستطيع الكود المولَّد استخدامها.
String newId() => _uuid.v4();

/// أعمدة مشتركة: UUID + أوقات + حذف منطقي (تمهيدًا للمزامنة لاحقًا).
mixin BaseColumns on Table {
  TextColumn get id => text().clientDefault(newId)();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Folders extends Table with BaseColumns {
  TextColumn get parentId => text().nullable().references(Folders, #id)();
  TextColumn get name => text()();
}

class Notes extends Table with BaseColumns {
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get bodyMd => text().withDefault(const Constant(''))();
  TextColumn get folderId => text().nullable().references(Folders, #id)();
  BoolColumn get isDaily => boolean().withDefault(const Constant(false))();
  TextColumn get dailyDate => text().nullable()(); // yyyy-MM-dd

  @override
  List<Set<Column>> get uniqueKeys => [
        {dailyDate}, // ملاحظة يومية واحدة لكل تاريخ
      ];
}

class NoteVersions extends Table with BaseColumns {
  TextColumn get noteId => text().references(Notes, #id)();
  TextColumn get title => text()();
  TextColumn get bodyMd => text()();
}

class Tags extends Table with BaseColumns {
  TextColumn get name => text().unique()();
}

class NoteTags extends Table {
  TextColumn get noteId => text().references(Notes, #id)();
  TextColumn get tagId => text().references(Tags, #id)();
  @override
  Set<Column> get primaryKey => {noteId, tagId};
}

/// الروابط الداخلية [[...]] بين الملاحظات.
class Links extends Table {
  TextColumn get sourceNoteId => text().references(Notes, #id)();
  TextColumn get targetNoteId => text().references(Notes, #id)();
  @override
  Set<Column> get primaryKey => {sourceNoteId, targetNoteId};
}

class Attachments extends Table with BaseColumns {
  TextColumn get noteId => text().references(Notes, #id)();
  TextColumn get relativePath => text()();
  TextColumn get mime => text()();
  IntColumn get sizeBytes => integer()();
  TextColumn get sha256 => text()();
}

class Projects extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get archivedAt => dateTime().nullable()();
}

class Tasks extends Table with BaseColumns {
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('todo'))();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  DateTimeColumn get dueAt => dateTime().nullable()();
  DateTimeColumn get remindAt => dateTime().nullable()();
  TextColumn get projectId => text().nullable().references(Projects, #id)();
  TextColumn get parentTaskId => text().nullable().references(Tasks, #id)();
  TextColumn get recurrenceRule => text().nullable()(); // RRULE
  DateTimeColumn get completedAt => dateTime().nullable()();
}

class TaskDeps extends Table {
  TextColumn get taskId => text().references(Tasks, #id)();
  TextColumn get dependsOnId => text().references(Tasks, #id)();
  @override
  Set<Column> get primaryKey => {taskId, dependsOnId};
}

class Habits extends Table with BaseColumns {
  TextColumn get name => text()();
  /// check | count | duration
  TextColumn get kind => text().withDefault(const Constant('check'))();
  RealColumn get targetValue => real().withDefault(const Constant(1))();
  TextColumn get unit => text().nullable()();
  DateTimeColumn get pausedAt => dateTime().nullable()();
}

/// جدول العادة يتغير عبر الزمن دون المساس بالسجل القديم.
class HabitSchedules extends Table with BaseColumns {
  TextColumn get habitId => text().references(Habits, #id)();
  IntColumn get daysMask => integer()(); // بت لكل يوم (0..6)
  TextColumn get validFrom => text()(); // yyyy-MM-dd
  TextColumn get validTo => text().nullable()();
}

/// السجل مرتبط بـ habit_id لا بالاسم، فتعديل الاسم لا يفقد التاريخ.
class HabitLogs extends Table with BaseColumns {
  TextColumn get habitId => text().references(Habits, #id)();
  TextColumn get date => text()(); // yyyy-MM-dd
  RealColumn get value => real().withDefault(const Constant(0))();
  /// done | partial | skipped | excused
  TextColumn get status => text().withDefault(const Constant('done'))();

  @override
  List<Set<Column>> get uniqueKeys => [
        {habitId, date},
      ];
}
