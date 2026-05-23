/// Overall sync status of the SDK.
enum SyncState {
  idle,
  syncing,
  completed,
  failed,
  offline,
}

/// Detailed status of a sync operation.
class SyncStatus {
  final SyncState state;
  final int totalItems;
  final int processedItems;
  final int failedItems;
  final String? currentEntity;
  final String? errorMessage;
  final DateTime? startedAt;
  final DateTime? completedAt;

  SyncStatus({
    this.state = SyncState.idle,
    this.totalItems = 0,
    this.processedItems = 0,
    this.failedItems = 0,
    this.currentEntity,
    this.errorMessage,
    this.startedAt,
    this.completedAt,
  });

  double get progress =>
      totalItems > 0 ? processedItems / totalItems : 0.0;

  bool get isSyncing => state == SyncState.syncing;

  bool get isOffline => state == SyncState.offline;

  SyncStatus copyWith({
    SyncState? state,
    int? totalItems,
    int? processedItems,
    int? failedItems,
    String? currentEntity,
    String? errorMessage,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return SyncStatus(
      state: state ?? this.state,
      totalItems: totalItems ?? this.totalItems,
      processedItems: processedItems ?? this.processedItems,
      failedItems: failedItems ?? this.failedItems,
      currentEntity: currentEntity ?? this.currentEntity,
      errorMessage: errorMessage ?? this.errorMessage,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  @override
  String toString() =>
      'SyncStatus(state: $state, progress: ${(progress * 100).toStringAsFixed(0)}%, '
      '$processedItems/$totalItems, failed: $failedItems)';
}

/// Per-entity sync statistics.
class EntitySyncStats {
  final String entityType;
  final int localCount;
  final int dirtyCount;
  final int deletedCount;
  final int pendingQueueItems;

  EntitySyncStats({
    required this.entityType,
    required this.localCount,
    required this.dirtyCount,
    required this.deletedCount,
    required this.pendingQueueItems,
  });

  bool get hasUnsyncedChanges => dirtyCount > 0 || deletedCount > 0 || pendingQueueItems > 0;

  @override
  String toString() =>
      '$entityType: $localCount local, $dirtyCount dirty, $deletedCount deleted, '
      '$pendingQueueItems queued';
}