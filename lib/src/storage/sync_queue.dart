import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'local_database.dart';
import '../models/sync_queue_item.dart';

/// Manages the persistence and retrieval of sync queue items.
class SyncQueue {
  final LocalDatabase _db;
  final _uuid = const Uuid();

  SyncQueue(this._db);

  /// Enqueue a new operation.
  Future<SyncQueueItem> enqueue({
    required String entityType,
    required String entityId,
    required String operation,
    required String path,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    int maxAttempts = 5,
  }) async {
    final item = SyncQueueItem(
      id: _uuid.v4(),
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      path: path,
      body: body != null ? jsonEncode(body) : null,
      headers: headers != null ? jsonEncode(headers) : null,
      maxAttempts: maxAttempts,
    );

    final db = await _db.database;
    await db.insert(LocalDatabase.syncQueueTable, item.toMap());
    return item;
  }

  /// Get all pending items, ordered by creation time.
  Future<List<SyncQueueItem>> getPendingItems({int? limit}) async {
    final db = await _db.database;
    final rows = await db.query(
      LocalDatabase.syncQueueTable,
      where: "status = 'pending' AND attempts < max_attempts",
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map((r) => SyncQueueItem.fromMap(r)).toList();
  }

  /// Get items by entity type.
  Future<List<SyncQueueItem>> getItemsByEntity(String entityType) async {
    final db = await _db.database;
    final rows = await db.query(
      LocalDatabase.syncQueueTable,
      where: "entity_type = ? AND status = 'pending'",
      whereArgs: [entityType],
      orderBy: 'created_at ASC',
    );
    return rows.map((r) => SyncQueueItem.fromMap(r)).toList();
  }

  /// Count pending items.
  Future<int> pendingCount() async {
    final db = await _db.database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM ${LocalDatabase.syncQueueTable} "
        "WHERE status = 'pending' AND attempts < max_attempts",
      ),
    );
    return count ?? 0;
  }

  /// Count failed items (exhausted retries).
  Future<int> failedCount() async {
    final db = await _db.database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM ${LocalDatabase.syncQueueTable} "
        "WHERE status = 'failed' OR attempts >= max_attempts",
      ),
    );
    return count ?? 0;
  }

  /// Mark an item as in progress.
  Future<void> markInProgress(String id) async {
    final db = await _db.database;
    await db.update(
      LocalDatabase.syncQueueTable,
      {
        'status': 'in_progress',
        'last_attempt_at': DateTime.now().millisecondsSinceEpoch,
        'attempts': Sqflite.sql('attempts + 1'),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark an item as completed and remove it.
  Future<void> markCompleted(String id) async {
    final db = await _db.database;
    await db.delete(
      LocalDatabase.syncQueueTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark an item as failed (will be retried if attempts remain).
  Future<void> markFailed(String id) async {
    final db = await _db.database;
    // Check if attempts exhausted
    final rows = await db.query(
      LocalDatabase.syncQueueTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final item = SyncQueueItem.fromMap(rows.first);
    final newStatus = item.attempts >= item.maxAttempts ? 'failed' : 'pending';

    await db.update(
      LocalDatabase.syncQueueTable,
      {
        'status': newStatus,
        'last_attempt_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Remove a specific item.
  Future<void> remove(String id) async {
    final db = await _db.database;
    await db.delete(
      LocalDatabase.syncQueueTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Remove all completed and permanently failed items.
  Future<void> cleanup() async {
    final db = await _db.database;
    await db.delete(
      LocalDatabase.syncQueueTable,
      where: "status IN ('completed', 'failed') OR attempts >= max_attempts",
    );
  }

  /// Remove all items for a specific entity (e.g. after manual conflict resolution).
  Future<void> removeByEntity(String entityType, String entityId) async {
    final db = await _db.database;
    await db.delete(
      LocalDatabase.syncQueueTable,
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
    );
  }

  /// Get all items (for debugging / UI display).
  Future<List<SyncQueueItem>> getAllItems() async {
    final db = await _db.database;
    final rows = await db.query(
      LocalDatabase.syncQueueTable,
      orderBy: 'created_at ASC',
    );
    return rows.map((r) => SyncQueueItem.fromMap(r)).toList();
  }
}