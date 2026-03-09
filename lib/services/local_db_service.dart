import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDbService {
  LocalDbService._();

  static final LocalDbService instance = LocalDbService._();
  Database? _database;

  Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError('SQLite local DB is not supported on Web.');
    }

    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'field_agent_local.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _createLocalApiCache(db);
        await _createDraftTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createDraftTables(db);
        }
      },
    );
  }

  static Future<void> _createLocalApiCache(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_api_cache (
        cache_key TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createDraftTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS draft_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        local_order_id TEXT UNIQUE,
        bill_to_party_id TEXT,
        party_name TEXT,
        ship_to_party_id TEXT,
        delivery_party_name TEXT,
        delivery_point_id TEXT,
        delivery_point_name TEXT,
        goods_agency_id TEXT,
        goods_agency_name TEXT,
        visit_id TEXT,
        route_id TEXT,
        package_id TEXT,
        package_name TEXT,
        payment_deal_id TEXT,
        delivery_address TEXT,
        status TEXT NOT NULL DEFAULT 'draft',
        finalized_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        employee_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS draft_order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        draft_order_id INTEGER NOT NULL,
        item_id TEXT,
        item_name TEXT,
        quantity INTEGER NOT NULL DEFAULT 1,
        unit_price REAL NOT NULL DEFAULT 0,
        discount_percent REAL NOT NULL DEFAULT 0,
        special_remarks TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (draft_order_id) REFERENCES draft_orders(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> saveLocalData({
    required String cacheKey,
    required String payload,
  }) async {
    final db = await database;
    await db.insert(
      'local_api_cache',
      {
        'cache_key': cacheKey,
        'payload': payload,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns stored JSON payload for a cache key, or null if not found.
  Future<String?> getLocalData(String cacheKey) async {
    final db = await database;
    final rows = await db.query(
      'local_api_cache',
      columns: ['payload'],
      where: 'cache_key = ?',
      whereArgs: [cacheKey],
    );
    if (rows.isEmpty) return null;
    return rows.first['payload'] as String?;
  }
}
