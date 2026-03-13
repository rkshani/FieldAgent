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
      version: 8,
      onCreate: (db, version) async {
        await _createLocalApiCache(db);
        await _createDraftTables(db);
        await _createBookingsTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createDraftTables(db);
        }
        if (oldVersion < 3) {
          await _addOrderSerialNoColumnIfNeeded(db);
        }
        if (oldVersion < 4) {
          await _addOrderRemarksColumnIfNeeded(db);
        }
        if (oldVersion < 5) {
          await _addOrderUploadColumnsIfNeeded(db);
        }
        if (oldVersion < 6) {
          await _createBookingsTables(db);
        }
        if (oldVersion < 7) {
          // Safety migration: ensure bookings tables exist for users who already
          // had DB version 6 from earlier builds without these tables.
          await _createBookingsTables(db);
        }
        if (oldVersion < 8) {
          await _addDraftOrderHeaderParityColumnsIfNeeded(db);
          await _addDraftOrderItemParityColumnsIfNeeded(db);
          await _addBookingParityColumnsIfNeeded(db);
          await _addBookingItemParityColumnsIfNeeded(db);
        }
      },
    );
  }

  /// Android parity: bookings table (INSERT INTO bookings ...)
  static Future<void> _createBookingsTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS bookings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        draft_order_id INTEGER,
        orderby INTEGER NOT NULL,
        invdate TEXT NOT NULL,
        partyid TEXT NOT NULL,
        package_id TEXT NOT NULL,
        remarks TEXT,
        status INTEGER NOT NULL DEFAULT 1,
        employeeid TEXT NOT NULL,
        localinvno TEXT NOT NULL,
        deliverypoint TEXT,
        isandroid TEXT NOT NULL DEFAULT '1',
        delivery_party TEXT,
        deal_id TEXT,
        goodsagency_id TEXT,
        goodsagency_name TEXT,
        delivery_party_remarks TEXT,
        delivery_point_remarks TEXT,
        visit_id TEXT,
        city_id TEXT,
        loc TEXT,
        routeid TEXT,
        uploaded TEXT NOT NULL DEFAULT 'NO',
        uploaded_at TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (draft_order_id) REFERENCES draft_orders(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS booking_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        booking_id INTEGER NOT NULL,
        item_id TEXT,
        item_name TEXT,
        quantity INTEGER NOT NULL DEFAULT 1,
        unit_price REAL NOT NULL DEFAULT 0,
        discount_percent REAL NOT NULL DEFAULT 0,
        remarks TEXT,
        direction_store TEXT,
        special_remarks TEXT,
        special_price REAL NOT NULL DEFAULT 0,
        subitem_id TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (booking_id) REFERENCES bookings(id) ON DELETE CASCADE
      )
    ''');
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
        order_serial_no INTEGER,
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
        city_id TEXT,
        loc TEXT,
        package_id TEXT,
        package_name TEXT,
        payment_deal_id TEXT,
        delivery_address TEXT,
        delivery_party_remarks TEXT,
        delivery_point_remarks TEXT,
        order_remarks TEXT,
        status TEXT NOT NULL DEFAULT 'draft',
        finalize_flag TEXT NOT NULL DEFAULT '0',
        uploaded TEXT NOT NULL DEFAULT 'NO',
        uploaded_at TEXT,
        finalized_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        employee_id TEXT
      )
    ''');
    await _addOrderSerialNoColumnIfNeeded(db);
    await _addOrderRemarksColumnIfNeeded(db);
    await _addOrderUploadColumnsIfNeeded(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS draft_order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        draft_order_id INTEGER NOT NULL,
        item_id TEXT,
        item_name TEXT,
        quantity INTEGER NOT NULL DEFAULT 1,
        unit_price REAL NOT NULL DEFAULT 0,
        discount_percent REAL NOT NULL DEFAULT 0,
        remarks TEXT,
        direction_store TEXT,
        special_remarks TEXT,
        special_price REAL NOT NULL DEFAULT 0,
        subitem_id TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (draft_order_id) REFERENCES draft_orders(id) ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> _addOrderSerialNoColumnIfNeeded(Database db) async {
    try {
      await db.execute(
        'ALTER TABLE draft_orders ADD COLUMN order_serial_no INTEGER',
      );
    } catch (_) {
      // Column already exists or table doesn't exist yet; safe to ignore.
    }
  }

  static Future<void> _addOrderRemarksColumnIfNeeded(Database db) async {
    try {
      await db.execute(
        'ALTER TABLE draft_orders ADD COLUMN order_remarks TEXT',
      );
    } catch (_) {
      // Column already exists or table doesn't exist yet; safe to ignore.
    }
  }

  static Future<void> _addOrderUploadColumnsIfNeeded(Database db) async {
    try {
      await db.execute(
        "ALTER TABLE draft_orders ADD COLUMN finalize_flag TEXT NOT NULL DEFAULT '0'",
      );
    } catch (_) {
      // Column already exists or table doesn't exist yet; safe to ignore.
    }

    try {
      await db.execute(
        "ALTER TABLE draft_orders ADD COLUMN uploaded TEXT NOT NULL DEFAULT 'NO'",
      );
    } catch (_) {
      // Column already exists or table doesn't exist yet; safe to ignore.
    }

    try {
      await db.execute('ALTER TABLE draft_orders ADD COLUMN uploaded_at TEXT');
    } catch (_) {
      // Column already exists or table doesn't exist yet; safe to ignore.
    }
  }

  static Future<void> _addDraftOrderHeaderParityColumnsIfNeeded(
    Database db,
  ) async {
    try {
      await db.execute('ALTER TABLE draft_orders ADD COLUMN city_id TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE draft_orders ADD COLUMN loc TEXT');
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE draft_orders ADD COLUMN delivery_party_remarks TEXT',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE draft_orders ADD COLUMN delivery_point_remarks TEXT',
      );
    } catch (_) {}
  }

  static Future<void> _addDraftOrderItemParityColumnsIfNeeded(
    Database db,
  ) async {
    try {
      await db.execute('ALTER TABLE draft_order_items ADD COLUMN remarks TEXT');
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE draft_order_items ADD COLUMN direction_store TEXT',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE draft_order_items ADD COLUMN special_price REAL NOT NULL DEFAULT 0',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE draft_order_items ADD COLUMN subitem_id TEXT',
      );
    } catch (_) {}
  }

  static Future<void> _addBookingParityColumnsIfNeeded(Database db) async {
    try {
      await db.execute('ALTER TABLE bookings ADD COLUMN goodsagency_name TEXT');
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE bookings ADD COLUMN delivery_party_remarks TEXT',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE bookings ADD COLUMN delivery_point_remarks TEXT',
      );
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE bookings ADD COLUMN visit_id TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE bookings ADD COLUMN city_id TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE bookings ADD COLUMN loc TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE bookings ADD COLUMN routeid TEXT');
    } catch (_) {}
  }

  static Future<void> _addBookingItemParityColumnsIfNeeded(Database db) async {
    try {
      await db.execute('ALTER TABLE booking_items ADD COLUMN remarks TEXT');
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE booking_items ADD COLUMN direction_store TEXT',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE booking_items ADD COLUMN special_remarks TEXT',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE booking_items ADD COLUMN special_price REAL NOT NULL DEFAULT 0',
      );
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE booking_items ADD COLUMN subitem_id TEXT');
    } catch (_) {}
  }

  Future<void> saveLocalData({
    required String cacheKey,
    required String payload,
  }) async {
    final db = await database;
    await db.insert('local_api_cache', {
      'cache_key': cacheKey,
      'payload': payload,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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

  /// Returns the full cache row for diagnostics, or null if missing.
  Future<Map<String, dynamic>?> getCacheRow(String cacheKey) async {
    final db = await database;
    final rows = await db.query(
      'local_api_cache',
      columns: ['cache_key', 'payload', 'updated_at'],
      where: 'cache_key = ?',
      whereArgs: [cacheKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }
}
