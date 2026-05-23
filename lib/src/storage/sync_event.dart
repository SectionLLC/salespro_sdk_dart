import '../models/sync_status.dart';

/// Callback signatures for sync lifecycle events.
typedef SyncStatusCallback = void Function(SyncStatus status);
typedef SyncErrorCallback = void Function(String entityType, String entityId, Object error);
typedef ConnectivityChangedCallback = void Function(bool isOnline);

/// Event system for observing sync and connectivity changes.
class SyncEventBus {
  final List<SyncStatusCallback> _statusListeners = [];
  final List<SyncErrorCallback> _errorListeners = [];
  final List<ConnectivityChangedCallback> _connectivityListeners = [];
  final List<VoidCallback> _syncCompletedListeners = [];

  /// Register a callback for sync status changes.
  void onStatusChanged(SyncStatusCallback callback) {
    _statusListeners.add(callback);
  }

  /// Register a callback for sync errors.
  void onError(SyncErrorCallback callback) {
    _errorListeners.add(callback);
  }

  /// Register a callback for connectivity changes.
  void onConnectivityChanged(ConnectivityChangedCallback callback) {
    _connectivityListeners.add(callback);
  }

  /// Register a callback for sync completion.
  void onSyncCompleted(VoidCallback callback) {
    _syncCompletedListeners.add(callback);
  }

  /// Remove all listeners for a given callback.
  void removeListener(dynamic callback) {
    _statusListeners.remove(callback);
    _errorListeners.remove(callback);
    _connectivityListeners.remove(callback);
    _syncCompletedListeners.remove(callback);
  }

  /// Remove all listeners.
  void removeAllListeners() {
    _statusListeners.clear();
    _errorListeners.clear();
    _connectivityListeners.clear();
    _syncCompletedListeners.clear();
  }

  // ── Internal emitters ──────────────────────────────────

  void emitStatus(SyncStatus status) {
    for (final cb in _statusListeners) {
      cb(status);
    }
  }

  void emitError(String entityType, String entityId, Object error) {
    for (final cb in _errorListeners) {
      cb(entityType, entityId, error);
    }
  }

  void emitConnectivityChanged(bool isOnline) {
    for (final cb in _connectivityListeners) {
      cb(isOnline);
    }
  }

  void emitSyncCompleted() {
    for (final cb in _syncCompletedListeners) {
      cb();
    }
  }
}