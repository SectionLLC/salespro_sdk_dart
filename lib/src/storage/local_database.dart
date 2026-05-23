import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// SQLite-backed local storage for all ERP entities and the sync queue.
class LocalDatabase {
  static const String _dbName = 'salespro_sdk.db';
  static const int _dbVersion = 1;

  Database? _db;

  // Table names
  static const String contactsTable = 'contacts';
  static const String productsTable = 'products';
  static const String ordersTable = 'orders';
  static const String invoicesTable = 'invoices';
  static const String quotesTable = 'quotes';
  static const String inventoryTable = 'inventory_items';
  static const String reportsTable = 'reports';
  static const String syncQueueTable = 'sync_queue';

  /// Open (or create) the database.
  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // ── Contacts ────────────────────────────────────────
    await db.execute('''
      CREATE TABLE $contactsTable (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        is_dirty INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ── Products ────────────────────────────────────────
    await db.execute('''
      CREATE TABLE $productsTable (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        is_dirty INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ── Orders ──────────────────────────────────────────
    await db.execute('''
      CREATE TABLE $ordersTable (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        is_dirty INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ── Invoices ────────────────────────────────────────
    await db.execute('''
      CREATE TABLE $invoicesTable (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        is_dirty INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ── Quotes ──────────────────────────────────────────
    await db.execute('''
      CREATE TABLE $quotesTable (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        is_dirty INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ── Inventory ───────────────────────────────────────
    await db.execute('''
      CREATE TABLE $inventoryTable (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        is_dirty INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ── Reports ─────────────────────────────────────────
    await db.execute('''
      CREATE TABLE $reportsTable (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        is_dirty INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ── Sync Queue ──────────────────────────────────────
    await db.execute('''
      CREATE TABLE $syncQueueTable (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        path TEXT NOT NULL,
        body TEXT,
        headers TEXT,
        attempts INTEGER NOT NULL DEFAULT 0,
        max_attempts INTEGER NOT NULL DEFAULT 5,
        created_at INTEGER NOT NULL,
        last_attempt_at INTEGER,
        status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    // Indexes for fast queries
    await db.execute(
      'CREATE INDEX idx_sync_queue_status ON $syncQueueTable (status)',
    );
    await db.execute(
      'CREATE INDEX idx_sync_queue_entity ON $syncQueueTable (entity_type, entity_id)',
    );
    await db.execute(
      'CREATE INDEX idx_contacts_dirty ON $contactsTable (is_dirty)',
    );
    await db.execute(
      'CREATE INDEX idx_products_dirty ON $productsTable (is_dirty)',
    );
    await db.execute(
      'CREATE INDEX idx_orders_dirty ON $ordersTable (is_dirty)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle future schema migrations here
  }

  // ── Generic CRUD for entity tables ──────────────────────

  /// Insert or replace an entity row.
  Future<void> upsertEntity(
    String table,
    String id,
    Map<String, dynamic> data, {
    bool isDirty = false,
  }) async {
    final db = await database;
    await db.insert(
      table,
      {
        'id': id,
        'data': jsonEncode(data),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'is_dirty': isDirty ? 1 : 0,
        'is_deleted': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Mark an entity as deleted (soft delete).
  Future<void> softDeleteEntity(String table, String id) async {
    final db = await database;
    await db.update(
      table,
      {
        'is_deleted': 1,
        'is_dirty': 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Hard delete an entity row.
  Future<void> deleteEntity(String table, String id) async {
    final db = await database;
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  /// Get a single entity by ID.
  Future<Map<String, dynamic>?> getEntity(String table, String id) async {
    final db = await database;
    final rows = await db.query(
      table,
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['data'] as String) as Map<String, dynamic>;
  }

  /// Get all entities from a table (non-deleted).
  Future<List<Map<String, dynamic>>> getAllEntities(
    String table, {
    int? limit,
    int? offset,
    String? whereClause,
    List<Object?>? whereArgs,
    String? orderBy,
  }) async {
    final db = await database;
    final rows = await db.query(
      table,
      where: 'is_deleted = 0${whereClause != null ? ' AND $whereClause' : ''}',
      whereArgs: whereArgs,
      limit: limit,
      offset: offset,
      orderBy: orderBy ?? 'updated_at DESC',
    );
    return rows
        .map((row) => jsonDecode(row['data'] as String) as Map<String, dynamic>)
        .toList();
  }

  /// Get all dirty (unsynced) entities.
  Future<List<Map<String, dynamic>>> getDirtyEntities(String table) async {
    final db = await database;
    final rows = await db.query(
      table,
      where: 'is_dirty = 1 AND is_deleted = 0',
      orderBy: 'updated_at ASC',
    );
    return rows
        .map((row) => jsonDecode(row['data'] as String) as Map<String, dynamic>)
        .toList();
  }

  /// Get all soft-deleted entities that haven't been synced yet.
  Future<List<String>> getDeletedEntityIds(String table) async {
    final db = await database;
    final rows = await db.query(
      table,
      columns: ['id'],
      where: 'is_deleted = 1 AND is_dirty = 1',
    );
    return rows.map((row) => row['id'] as String).toList();
  }

  /// Mark an entity as clean (successfully synced).
  Future<void> markEntityClean(String table, String id) async {
    final db = await database;
    await db.update(
      table,
      {'is_dirty': 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Count entities in a table.
  Future<int> countEntities(String table, {bool? onlyDirty, bool? includeDeleted}) async {
    final db = await database;
    var where = <String>[];
    var args = <Object?>[];
    if (onlyDirty == true) { where.add('is_dirty = 1'); }
    if (includeDeleted != true) { where.add('is_deleted = 0'); }
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM $table${where.isNotEmpty ? ' WHERE ${where.join(' AND ')}' : ''}',
        args,
      ),
    );
    return count ?? 0;
  }

  /// Clear all local data (useful for logout).
  Future<void> clearAll() async {
    final db = await database;
    await db.delete(contactsTable);
    await db.delete(productsTable);
    await db.delete(ordersTable);
    await db.delete(invoicesTable);
    await db.delete(quotesTable);
    await db.delete(inventoryTable);
    await db.delete(reportsTable);
    await db.delete(syncQueueTable);
  }

  /// Clear only the sync queue.
  Future<void> clearSyncQueue() async {
    final db = await database;
    await db.delete(syncQueueTable);
  }

  /// Close the database.
  Future<void> close() async {
    final db = await database;
    await db.close();
    _db = null;
  }
}