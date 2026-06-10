import 'dart:async';
import 'dart:convert';

import 'local_database.dart';
import 'sync_queue.dart';
import 'connectivity_monitor.dart';
import 'sync_event.dart';
import '../client/http_client.dart';
import '../config/sdk_config.dart';
import '../models/sync_queue_item.dart';
import '../models/sync_status.dart';
import '../exceptions/sdk_exceptions.dart';

/// Coordinates the synchronization of local changes with the remote ERP.
class SyncManager {
  final LocalDatabase _localDb;
  final SyncQueue _syncQueue;
  final ConnectivityMonitor _connectivityMonitor;
  final SyncEventBus _eventBus;
  final SalesProHttpClient _httpClient;
  final SalesProConfig _config;

  SyncStatus _status = SyncStatus();
  bool _autoSyncEnabled = true;
  Timer? _periodicTimer;
  ConnectivityChangedCallback? _connectivityCallback;

  SyncManager({
    required LocalDatabase localDb,
    required SyncQueue syncQueue,
    required ConnectivityMonitor connectivityMonitor,
    required SyncEventBus eventBus,
    required SalesProHttpClient httpClient,
    required SalesProConfig config,
  })  : _localDb = localDb,
        _syncQueue = syncQueue,
        _connectivityMonitor = connectivityMonitor,
        _eventBus = eventBus,
        _httpClient = httpClient,
        _config = config;

  SyncStatus get status => _status;
  bool get autoSyncEnabled => _autoSyncEnabled;
  bool get isOnline => _connectivityMonitor.isOnline;
  SyncEventBus get events => _eventBus;

  // ── Lifecycle ────────────────────────────────────────────

  Future<void> init() async {
    await _connectivityMonitor.start();

    _connectivityCallback = (isOnline) {
      if (isOnline && _autoSyncEnabled) {
        syncAll();
      } else if (!isOnline) {
        _updateStatus(_status.copyWith(state: SyncState.offline));
      }
    };

    _eventBus.onConnectivityChanged(_connectivityCallback!);

    _periodicTimer = Timer.periodic(
      _config.syncInterval ?? const Duration(minutes: 5),
      (_) {
        if (_autoSyncEnabled && _connectivityMonitor.isOnline) {
          syncAll();
        }
      },
    );

    if (_connectivityMonitor.isOnline && _autoSyncEnabled) {
      await syncAll();
    }
  }

  void dispose() {
    _periodicTimer?.cancel();
    if (_connectivityCallback != null) {
      _eventBus.removeListener(_connectivityCallback);
    }
    _connectivityMonitor.stop();
  }

  void setAutoSync(bool enabled) {
    _autoSyncEnabled = enabled;
  }

  // ── Sync Operations ─────────────────────────────────────

  Future<SyncStatus> syncAll() async {
    if (_status.isSyncing) {
      return _status;
    }

    if (!_connectivityMonitor.isOnline) {
      _updateStatus(_status.copyWith(state: SyncState.offline));
      return _status;
    }

    final startedAt = DateTime.now();
    _updateStatus(SyncStatus(
      state: SyncState.syncing,
      startedAt: startedAt,
    ));

    try {
      await _processSyncQueue();
      await _pushDirtyEntities();
      await _pullRemoteUpdates();

      // Cleanup removes completed items AND items that failed 3 times (ignored)
      await _syncQueue.cleanup();

      final completedStatus = SyncStatus(
        state: SyncState.completed,
        startedAt: startedAt,
        completedAt: DateTime.now(),
      );
      _updateStatus(completedStatus);
      _eventBus.emitSyncCompleted();

      return completedStatus;
    } catch (e) {
      final failedStatus = SyncStatus(
        state: SyncState.failed,
        startedAt: startedAt,
        errorMessage: e.toString(),
      );
      _updateStatus(failedStatus);
      return failedStatus;
    }
  }

  Future<void> _processSyncQueue() async {
    final items = await _syncQueue.getPendingItems();

    if (items.isEmpty) {
      return;
    }

    _updateStatus(_status.copyWith(
      totalItems: items.length,
      processedItems: 0,
    ));

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      _updateStatus(_status.copyWith(
        currentEntity: '${item.entityType}/${item.entityId}',
      ));

      await _processQueueItem(item);

      _updateStatus(_status.copyWith(
        processedItems: i + 1,
      ));
    }
  }

  Future<void> _processQueueItem(SyncQueueItem item) async {
    // Mark as in progress (increments attempts by 1 via rawUpdate)
    await _syncQueue.markInProgress(item.id!);

    try {
      final body = item.body != null
          ? jsonDecode(item.body!) as Map<String, dynamic>
          : null;

      switch (item.operation) {
        case 'create':
          await _httpClient.post(item.path, body: body);
          break;
        case 'update':
          await _httpClient.put(item.path, body: body);
          break;
        case 'patch':
          await _httpClient.patch(item.path, body: body);
          break;
        case 'delete':
          await _httpClient.delete(item.path);
          break;
        default:
          throw SalesProException(
              message: 'Unknown operation: ${item.operation}');
      }

      // Success — remove from queue and mark entity clean
      await _syncQueue.markCompleted(item.id!);
      await _localDb.markEntityClean(
        _entityTypeToTable(item.entityType),
        item.entityId,
      );

      if (item.operation == 'delete') {
        await _localDb.deleteEntity(
          _entityTypeToTable(item.entityType),
          item.entityId,
        );
      }
    } catch (e) {
      // Mark as failed. This returns the updated item so we can check attempts.
      final updatedItem = await _syncQueue.markFailed(item.id!);

      _eventBus.emitError(item.entityType, item.entityId, e);

      // NEW: If the item has exhausted its 3 retries, emit a specific event
      // so the app knows it's being ignored. The cleanup() function will delete it.
      if (updatedItem != null && updatedItem.isExhausted) {
        _eventBus.emitError(
          item.entityType,
          item.entityId,
          SalesProException(
            message:
                'Sync item ignored after ${updatedItem.maxAttempts} failed attempts.',
            statusCode: 0,
          ),
        );
      }
    }
  }

  Future<void> _pushDirtyEntities() async {
    final entityTypes = [
      'contact',
      'product',
      'order',
      'invoice',
      'quote',
      'inventory_item'
    ];

    for (final type in entityTypes) {
      final table = _entityTypeToTable(type);
      final dirtyEntities = await _localDb.getDirtyEntities(table);

      for (final entity in dirtyEntities) {
        final id = entity['id']?.toString();
        if (id == null) {
          continue;
        }

        final existing = await _syncQueue.getItemsByEntity(type);
        if (existing.any((e) => e.entityId == id)) {
          continue;
        }

        await _syncQueue.enqueue(
          entityType: type,
          entityId: id,
          operation: 'update',
          path: '/$type/$id',
          body: entity,
        );
      }

      final deletedIds = await _localDb.getDeletedEntityIds(table);
      for (final id in deletedIds) {
        final existing = await _syncQueue.getItemsByEntity(type);
        if (existing.any((e) => e.entityId == id && e.operation == 'delete')) {
          continue;
        }

        await _syncQueue.enqueue(
          entityType: type,
          entityId: id,
          operation: 'delete',
          path: '/$type/$id',
        );
      }
    }
  }

  Future<void> _pullRemoteUpdates() async {
    // Pull contacts
    try {
      final response = await _httpClient.get('/contacts', queryParams: {
        'updated_since': _config.lastSyncTimestamp?.toIso8601String(),
      });
      final items = (response.data as Map?)?['data'] as List? ?? [];
      for (final item in items) {
        final map = item as Map<String, dynamic>;
        final id = map['id']?.toString();
        if (id != null) {
          await _localDb.upsertEntity(LocalDatabase.contactsTable, id, map);
        }
      }
    } catch (_) {}

    // Pull products
    try {
      final response = await _httpClient.get('/products', queryParams: {
        'updated_since': _config.lastSyncTimestamp?.toIso8601String(),
      });
      final items = (response.data as Map?)?['data'] as List? ?? [];
      for (final item in items) {
        final map = item as Map<String, dynamic>;
        final id = map['id']?.toString();
        if (id != null) {
          await _localDb.upsertEntity(LocalDatabase.productsTable, id, map);
        }
      }
    } catch (_) {}

    // Pull orders
    try {
      final response = await _httpClient.get('/orders', queryParams: {
        'updated_since': _config.lastSyncTimestamp?.toIso8601String(),
      });
      final items = (response.data as Map?)?['data'] as List? ?? [];
      for (final item in items) {
        final map = item as Map<String, dynamic>;
        final id = map['id']?.toString();
        if (id != null) {
          await _localDb.upsertEntity(LocalDatabase.ordersTable, id, map);
        }
      }
    } catch (_) {}

    // Pull invoices
    try {
      final response = await _httpClient.get('/invoices', queryParams: {
        'updated_since': _config.lastSyncTimestamp?.toIso8601String(),
      });
      final items = (response.data as Map?)?['data'] as List? ?? [];
      for (final item in items) {
        final map = item as Map<String, dynamic>;
        final id = map['id']?.toString();
        if (id != null) {
          await _localDb.upsertEntity(LocalDatabase.invoicesTable, id, map);
        }
      }
    } catch (_) {}

    // Pull quotes
    try {
      final response = await _httpClient.get('/quotes', queryParams: {
        'updated_since': _config.lastSyncTimestamp?.toIso8601String(),
      });
      final items = (response.data as Map?)?['data'] as List? ?? [];
      for (final item in items) {
        final map = item as Map<String, dynamic>;
        final id = map['id']?.toString();
        if (id != null) {
          await _localDb.upsertEntity(LocalDatabase.quotesTable, id, map);
        }
      }
    } catch (_) {}

    _config.lastSyncTimestamp = DateTime.now();
  }

  // ── Stats & Info ────────────────────────────────────────

  Future<List<EntitySyncStats>> getStats() async {
    final types = [
      ('contact', LocalDatabase.contactsTable),
      ('product', LocalDatabase.productsTable),
      ('order', LocalDatabase.ordersTable),
      ('invoice', LocalDatabase.invoicesTable),
      ('quote', LocalDatabase.quotesTable),
      ('inventory_item', LocalDatabase.inventoryTable),
    ];

    final stats = <EntitySyncStats>[];
    for (final (type, table) in types) {
      final localCount = await _localDb.countEntities(table);
      final dirtyCount = await _localDb.countEntities(table, onlyDirty: true);
      final totalWithDeleted =
          await _localDb.countEntities(table, includeDeleted: true);
      final deletedCount = totalWithDeleted - localCount;
      final queueItems = await _syncQueue.getItemsByEntity(type);

      stats.add(EntitySyncStats(
        entityType: type,
        localCount: localCount,
        dirtyCount: dirtyCount,
        deletedCount: deletedCount > 0 ? deletedCount : 0,
        pendingQueueItems: queueItems.length,
      ));
    }
    return stats;
  }

  // ── Helpers ──────────────────────────────────────────────

  void _updateStatus(SyncStatus newStatus) {
    _status = newStatus;
    _eventBus.emitStatus(newStatus);
  }

  String _entityTypeToTable(String type) {
    switch (type) {
      case 'contact':
        return LocalDatabase.contactsTable;
      case 'product':
        return LocalDatabase.productsTable;
      case 'order':
        return LocalDatabase.ordersTable;
      case 'invoice':
        return LocalDatabase.invoicesTable;
      case 'quote':
        return LocalDatabase.quotesTable;
      case 'inventory_item':
        return LocalDatabase.inventoryTable;
      default:
        return type;
    }
  }
}
