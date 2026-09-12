import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/transaction.dart';

/// Local-first cache: a transaction is saved here immediately and shown in
/// the UI right away, independent of whether/when it has synced to the API.
class DbService {
  static Database? _db;

  static Future<Database> _open() async {
    if (_db != null) return _db!;

    // sqflite only ships mobile (Android/iOS) plugin implementations;
    // desktop/test environments need sqflite_common_ffi's factory instead.
    // This only matters for dev/testing on Windows and `flutter test` - the
    // real target is Android, where the default sqflite factory (and
    // path_provider, which needs a platform channel `flutter test`'s
    // headless harness doesn't provide) is used untouched.
    final String path;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      path = join(Directory.systemTemp.path, 'money_handler.db');
    } else {
      final dir = await getApplicationDocumentsDirectory();
      path = join(dir.path, 'money_handler.db');
    }

    _db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE transactions (
              client_transaction_id TEXT PRIMARY KEY,
              year INTEGER NOT NULL,
              month INTEGER NOT NULL,
              date TEXT NOT NULL,
              type TEXT NOT NULL,
              category TEXT NOT NULL,
              subcategory TEXT NOT NULL,
              item TEXT NOT NULL,
              amount REAL NOT NULL,
              classification TEXT,
              notes TEXT,
              synced INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await _createCacheTable(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await _createCacheTable(db);
        },
      ),
    );
    return _db!;
  }

  static Future<void> _createCacheTable(Database db) => db.execute('''
        CREATE TABLE IF NOT EXISTS kv_cache (
          cache_key TEXT PRIMARY KEY,
          json_value TEXT NOT NULL,
          updated_at_ms INTEGER NOT NULL
        )
      ''');

  /// Generic cache used for everything that isn't a transaction (setup,
  /// income, plan, summary) - populated only by an explicit sync
  /// (SyncService.syncPending / RefreshService), never by a screen opening
  /// itself. Screens read this instead of calling the API directly, so
  /// navigating around the app costs zero network requests.
  static Future<void> setCache(String key, Object value) async {
    final db = await _open();
    await db.insert(
      'kv_cache',
      {
        'cache_key': key,
        'json_value': jsonEncode(value),
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns (value, updatedAt) or null if never cached.
  static Future<(dynamic, DateTime)?> getCache(String key) async {
    final db = await _open();
    final rows = await db.query('kv_cache', where: 'cache_key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return (
      jsonDecode(row['json_value'] as String),
      DateTime.fromMillisecondsSinceEpoch(row['updated_at_ms'] as int),
    );
  }

  static Future<void> insert(LocalTransaction tx) async {
    final db = await _open();
    await db.insert('transactions', tx.toDbMap());
  }

  /// Used when importing transactions that already exist server-side (e.g.
  /// entered directly in Excel, or from another device) - ignores rows
  /// whose id we already have locally instead of overwriting local edits.
  static Future<void> insertOrIgnore(LocalTransaction tx) async {
    final db = await _open();
    await db.insert('transactions', tx.toDbMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<List<LocalTransaction>> listAll() async {
    final db = await _open();
    final rows = await db.query('transactions', orderBy: 'date DESC, rowid DESC');
    return rows.map(LocalTransaction.fromDbMap).toList();
  }

  static Future<List<LocalTransaction>> listForMonth(int year, int month) async {
    final db = await _open();
    final rows = await db.query(
      'transactions',
      where: 'year = ? AND month = ?',
      whereArgs: [year, month],
      orderBy: 'date DESC, rowid DESC',
    );
    return rows.map(LocalTransaction.fromDbMap).toList();
  }

  static Future<List<LocalTransaction>> listUnsynced() async {
    final db = await _open();
    final rows = await db.query('transactions', where: 'synced = 0');
    return rows.map(LocalTransaction.fromDbMap).toList();
  }

  static Future<void> markSynced(Iterable<String> clientTransactionIds) async {
    if (clientTransactionIds.isEmpty) return;
    final db = await _open();
    final placeholders = List.filled(clientTransactionIds.length, '?').join(',');
    await db.update(
      'transactions',
      {'synced': 1},
      where: 'client_transaction_id IN ($placeholders)',
      whereArgs: clientTransactionIds.toList(),
    );
  }

  /// Replaces a transaction's editable fields in place, keeping its id and
  /// synced flag as given by the caller (the caller decides whether an edit
  /// to an already-synced row should flip synced back to false).
  static Future<void> update(LocalTransaction tx) async {
    final db = await _open();
    await db.update(
      'transactions',
      tx.toDbMap(),
      where: 'client_transaction_id = ?',
      whereArgs: [tx.clientTransactionId],
    );
  }

  static Future<void> delete(String clientTransactionId) async {
    final db = await _open();
    await db.delete(
      'transactions',
      where: 'client_transaction_id = ?',
      whereArgs: [clientTransactionId],
    );
  }
}
