import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'sync_event.dart';

/// Monitors device connectivity and emits events when status changes.
class ConnectivityMonitor {
  final Connectivity _connectivity = Connectivity();
  final SyncEventBus _eventBus;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isOnline = true;
  bool _initialized = false;

  ConnectivityMonitor(this._eventBus);

  /// Whether the device currently has internet connectivity.
  bool get isOnline => _isOnline;

  /// Start monitoring connectivity changes.
  Future<void> start() async {
    if (_initialized) return;
    _initialized = true;

    // Check initial state
    final results = await _connectivity.checkConnectivity();
    _isOnline = results.any((r) => r != ConnectivityResult.none);

    // Listen for changes
    _subscription = _connectivity.onConnectivityChanged.listen(_onChanged);
  }

  void _onChanged(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;
    _isOnline = results.any((r) => r != ConnectivityResult.none);

    if (wasOnline != _isOnline) {
      _eventBus.emitConnectivityChanged(_isOnline);
    }
  }

  /// Stop monitoring.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _initialized = false;
  }

  /// Perform a lightweight connectivity check.
  Future<bool> checkConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    _isOnline = results.any((r) => r != ConnectivityResult.none);
    return _isOnline;
  }
}