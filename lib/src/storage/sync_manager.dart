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
///
/// - Watches connectivity via [ConnectivityMonitor]
/// - Processes the [SyncQueue] when online
/// - Emits events via [SyncEventBus]
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
  StreamSubscription<bool>? _connectivitySub;

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

  /// Current sync status.
  SyncStatus get status => _status;

  /// Whether auto-sync is enabled.
  bool get autoSyncEnabled => _autoSyncEnabled;

  /// Whether the device is currently online.
  bool get isOnline => _connectivityMonitor.isOnline;

  /// The event bus for observing sync and connectivity events.
  SyncEventBus get events => _eventBus;

  // ── Lifecycle ────────────────────────────────────────────

  /// Initialize the sync manager: start connectivity monitoring and
  /// register the auto-sync trigger.
  Future<void> init() async {
    await _connectivityMonitor.start();

    _connectivitySub = _eventBus.onConnectivityChanged((isOnline) {
      if (isOnline && _autoSyncEnabled) {
        syncAll();
      } else if (!isOnline) {
        _updateStatus(_status.copyWith(state: SyncState.offline));
      }
    });

    // Periodic sync attempt (configurable interval)
    _periodicTimer = Timer.periodic(
      _config.syncInterval ?? const Duration(minutes: 5),
      (_) {
        if (_autoSyncEnabled && _connectivityMonitor.isOnline) {
          syncAll();
        }
      },
    );

    // If already online, do an initial sync
    if (_connectivityMonitor.isOnline && _autoSyncEnabled) {
      await syncAll();
    }
  }

  /// Stop all monitoring and timers.
  void dispose() {
    _periodicTimer?.cancel();
    _connectivitySub?.cancel();
    _connectivityMonitor.stop();
  }

  /// Enable or disable auto-sync.
  void setAutoSync(bool enabled) {
    _autoSyncEnabled = enabled;
  }

  // ── Sync Operations ─────────────────────────────────────

  /// Run a full sync cycle: push local changes → pull remote updates.
  Future<SyncStatus> syncAll() async {
    if (_status.isSyncing) return _status;
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
      // Phase 1: Push pending queue items to the server
      await _processSyncQueue();

      // Phase 2: Push dirty entities not yet in the queue
      await _pushDirtyEntities();

      // Phase 3: Pull latest from server
      await _pullRemoteUpdates();

      // Phase 4: Cleanup
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

  /// Process all pending items in the sync queue.
  Future<void> _processSyncQueue() async {
    final items = await _syncQueue.getPendingItems();

    if (items.isEmpty) return;

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

  /// Process a single sync queue item.
  Future<void> _processQueueItem(SyncQueueItem item) async {
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
          throw SalesProException(message: 'Unknown operation: ${item.operation}');
      }

      // Success — remove from queue and mark entity clean
      await _syncQueue.markCompleted(item.id!);
      await _localDb.markEntityClean(
        _entityTypeToTable(item.entityType),
        item.entityId,
      );

      // If it was a delete, also hard-delete the local row
      if (item.operation == 'delete') {
        await _localDb.deleteEntity(
          _entityTypeToTable(item.entityType),
          item.entityId,
        );
      }
    } catch (e) {
      _eventBus.emitError(item.entityType, item.entityId, e);
      await _syncQueue.markFailed(item.id!);
    }
  }

  /// Push dirty entities that aren't yet in the queue.
  Future<void> _pushDirtyEntities() async {
    final entityTypes = ['contact', 'product', 'order', 'invoice', 'quote', 'inventory_item'];

    for (final type in entityTypes) {
      final table = _entityTypeToTable(type);
      final dirtyEntities = await _localDb.getDirtyEntities(table);

      for (final entity in dirtyEntities) {
        final id = entity['id']?.toString();
        if (id == null) continue;

        // Check if already in queue to avoid duplicates
        final existing = await _syncQueue.getItemsByEntity(type);
        if (existing.any((e) => e.entityId == id)) continue;

        await _syncQueue.enqueue(
          entityType: type,
          entityId: id,
          operation: 'update',
          path: '/$type/$id',
          body: entity,
        );
      }

      // Handle soft-deleted entities
      final deletedIds = await _localDb.getDeletedEntityIds(table);
      for (final id in deletedIds) {
        final existing = await _syncQueue.getItemsByEntity(type);
        if (existing.any((e) => e.entityId == id && e.operation == 'delete')) continue;

        await _syncQueue.enqueue(
          entityType: type,
          entityId: id,
          operation: 'delete',
          path: '/$type/$id',
        );
      }
    }
  }

  /// Pull latest data from the server for each entity type.
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
    } catch (_) {
      // Silently continue — pull is best-effort
    }

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

    // Update last sync timestamp
    _config.lastSyncTimestamp = DateTime.now();
  }

  // ── Stats & Info ────────────────────────────────────────

  /// Get sync statistics for all entity types.
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
      final deletedCount = await _localDb.countEntities(table, includeDeleted: true)
          - localCount; // rough: total - non-deleted = deleted
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