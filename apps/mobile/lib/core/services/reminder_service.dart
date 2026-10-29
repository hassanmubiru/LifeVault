import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class Reminder {
  final String id;
  final String documentId;
  final String title;
  final String? note;
  final DateTime remindAt;
  final bool isRecurring;
  final String? recurringInterval;
  final bool isActive;
  final int createdAt;

  Reminder({
    required this.id,
    required this.documentId,
    required this.title,
    this.note,
    required this.remindAt,
    this.isRecurring = false,
    this.recurringInterval,
    this.isActive = true,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'document_id': documentId,
      'title': title,
      'note': note,
      'remind_at': remindAt.millisecondsSinceEpoch,
      'is_recurring': isRecurring ? 1 : 0,
      'recurring_interval': recurringInterval,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt,
    };
  }

  factory Reminder.fromMap(Map<String, dynamic> map) {
    return Reminder(
      id: map['id'] as String,
      documentId: map['document_id'] as String,
      title: map['title'] as String,
      note: map['note'] as String?,
      remindAt: DateTime.fromMillisecondsSinceEpoch(map['remind_at'] as int),
      isRecurring: (map['is_recurring'] as int) == 1,
      recurringInterval: map['recurring_interval'] as String?,
      isActive: (map['is_active'] as int) == 1,
      createdAt: map['created_at'] as int,
    );
  }
}

class ReminderService {
  static Database? _database;
  static const String _tableName = 'reminders';
  final _reminderController = StreamController<List<Reminder>>.broadcast();
  Timer? _checkTimer;

  Stream<List<Reminder>> get remindersStream => _reminderController.stream;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = p.join(await getDatabasesPath(), 'lifevault_reminders.db');
    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id TEXT PRIMARY KEY,
            document_id TEXT NOT NULL,
            title TEXT NOT NULL,
            note TEXT,
            remind_at INTEGER NOT NULL,
            is_recurring INTEGER DEFAULT 0,
            recurring_interval TEXT,
            is_active INTEGER DEFAULT 1,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_reminders_doc ON $_tableName(document_id)');
        await db.execute('CREATE INDEX idx_reminders_active ON $_tableName(is_active, remind_at)');
      },
    );
  }

  Future<void> addReminder(Reminder reminder) async {
    final db = await database;
    await db.insert(_tableName, reminder.toMap());
    _notifyListeners();
  }

  Future<void> updateReminder(Reminder reminder) async {
    final db = await database;
    await db.update(_tableName, reminder.toMap(), where: 'id = ?', whereArgs: [reminder.id]);
    _notifyListeners();
  }

  Future<void> deleteReminder(String id) async {
    final db = await database;
    await db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
    _notifyListeners();
  }

  Future<void> dismissReminder(String id) async {
    final db = await database;
    await db.update(
      _tableName,
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    _notifyListeners();
  }

  Future<List<Reminder>> getRemindersForDocument(String documentId) async {
    final db = await database;
    final maps = await db.query(
      _tableName,
      where: 'document_id = ? AND is_active = 1',
      whereArgs: [documentId],
      orderBy: 'remind_at ASC',
    );
    return maps.map((m) => Reminder.fromMap(m)).toList();
  }

  Future<List<Reminder>> getUpcomingReminders({int limit = 20}) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final maps = await db.query(
      _tableName,
      where: 'is_active = 1 AND remind_at >= ?',
      whereArgs: [now],
      orderBy: 'remind_at ASC',
      limit: limit,
    );
    return maps.map((m) => Reminder.fromMap(m)).toList();
  }

  Future<List<Reminder>> getDueReminders() async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final maps = await db.query(
      _tableName,
      where: 'is_active = 1 AND remind_at <= ?',
      whereArgs: [now],
      orderBy: 'remind_at ASC',
    );
    return maps.map((m) => Reminder.fromMap(m)).toList();
  }

  Future<void> snoozeReminder(String id, Duration duration) async {
    final db = await database;
    final newTime = DateTime.now().add(duration).millisecondsSinceEpoch;
    await db.update(
      _tableName,
      {'remind_at': newTime},
      where: 'id = ?',
      whereArgs: [id],
    );
    _notifyListeners();
  }

  void _notifyListeners() async {
    final reminders = await getUpcomingReminders();
    _reminderController.add(reminders);
  }

  void startPeriodicCheck() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _notifyListeners();
    });
  }

  void stopPeriodicCheck() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  void dispose() {
    stopPeriodicCheck();
    _reminderController.close();
  }
}