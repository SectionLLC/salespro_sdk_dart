/// SalesPro SDK for Flutter
///
/// A comprehensive SDK for connecting and communicating with
/// SalesPro ERP systems from Flutter applications.
library salespro_sdk;

// Core
export 'src/config/sdk_config.dart';
export 'src/client/http_client.dart';
export 'src/auth/auth_manager.dart';
export 'src/exceptions/sdk_exceptions.dart';

// Storage
export 'src/storage/local_database.dart';
export 'src/storage/sync_queue.dart';
export 'src/storage/connectivity_monitor.dart';
export 'src/storage/sync_manager.dart';
export 'src/storage/sync_event.dart';

// Models
export 'src/models/contact.dart';
export 'src/models/product.dart';
export 'src/models/order.dart';
export 'src/models/invoice.dart';
export 'src/models/quote.dart';
export 'src/models/inventory_item.dart';
export 'src/models/report.dart';
export 'src/models/api_response.dart';
export 'src/models/sync_queue_item.dart';
export 'src/models/sync_status.dart';

// Services
export 'src/services/contact_service.dart';
export 'src/services/product_service.dart';
export 'src/services/order_service.dart';
export 'src/services/invoice_service.dart';
export 'src/services/quote_service.dart';
export 'src/services/inventory_service.dart';
export 'src/services/report_service.dart';

import 'src/config/sdk_config.dart';
import 'src/client/http_client.dart';
import 'src/auth/auth_manager.dart';
import 'src/storage/local_database.dart';
import 'src/storage/sync_queue.dart';
import 'src/storage/connectivity_monitor.dart';
import 'src/storage/sync_manager.dart';
import 'src/storage/sync_event.dart';
import 'src/services/contact_service.dart';
import 'src/services/product_service.dart';
import 'src/services/order_service.dart';
import 'src/services/invoice_service.dart';
import 'src/services/quote_service.dart';
import 'src/services/inventory_service.dart';
import 'src/services/report_service.dart';
import 'src/models/sync_status.dart';

/// The main SDK class — single entry point for all ERP interactions
/// with offline-first storage and auto-sync.
class SalesProSDK {
  late final SalesProConfig _config;
  late final SalesProHttpClient _httpClient;
  late final AuthManager _authManager;

  // Storage
  LocalDatabase? _localDb;
  SyncQueue? _syncQueue;
  ConnectivityMonitor? _connectivityMonitor;
  SyncManager? _syncManager;
  SyncEventBus? _eventBus;

  // Services
  ContactService? _contactService;
  ProductService? _productService;
  OrderService? _orderService;
  InvoiceService? _invoiceService;
  QuoteService? _quoteService;
  InventoryService? _inventoryService;
  ReportService? _reportService;

  bool _initialized = false;

  SalesProSDK({required SalesProConfig config}) : _config = config {
    _httpClient = SalesProHttpClient(config: _config);
    _authManager = AuthManager(httpClient: _httpClient, config: _config);
  }
  /// Create an SDK instance with OAuth2 credentials.
  factory SalesProSDK.withOAuth2({
    required String baseUrl,
    required String clientId,
    required String clientSecret,
    String? scope,
    bool offlineEnabled = true,
  }) {
    return SalesProSDK(
      config: SalesProConfig(
        baseUrl: baseUrl,
        clientId: clientId,
        clientSecret: clientSecret,
        scope: scope,
        offlineEnabled: offlineEnabled,
      ),
    );
  }
  factory SalesProSDK.withApiKey({
    required String baseUrl,
    required String apiKey,
    bool offlineEnabled = true,
  }) {
    return SalesProSDK(
      config: SalesProConfig(
        baseUrl: baseUrl,
        apiKey: apiKey,
        offlineEnabled: offlineEnabled,
      ),
    );
  }

  // ── Initialization ──────────────────────────────────────

  /// Initialize the SDK: set up local storage, connectivity monitor,
  /// and start auto-sync.
  ///
  /// Must be called before using any service if `offlineEnabled` is true.
  Future<void> init() async {
    if (_initialized) return;

    if (_config.offlineEnabled) {
      _localDb = LocalDatabase();
      _syncQueue = SyncQueue(_localDb!);
      _connectivityMonitor = ConnectivityMonitor(_eventBus ??= SyncEventBus());
      _eventBus ??= SyncEventBus();

      _syncManager = SyncManager(
        localDb: _localDb!,
        syncQueue: _syncQueue!,
        connectivityMonitor: _connectivityMonitor!,
        eventBus: _eventBus!,
        httpClient: _httpClient,
        config: _config,
      );

      await _syncManager!.init();
    }

    _initialized = true;
  }

  // ── Getters ─────────────────────────────────────────────

  AuthManager get auth => _authManager;

  ContactService get contacts => _contactService ??= ContactService(
    httpClient: _httpClient,
    localDb: _localDb,
    syncQueue: _syncQueue,
    connectivityMonitor: _connectivityMonitor,
  );

  ProductService get products => _productService ??= ProductService(
    httpClient: _httpClient,
    localDb: _localDb,
    syncQueue: _syncQueue,
    connectivityMonitor: _connectivityMonitor,
  );

  OrderService get orders => _orderService ??= OrderService(
    httpClient: _httpClient,
    localDb: _localDb,
    syncQueue: _syncQueue,
    connectivityMonitor: _connectivityMonitor,
  );

  InvoiceService get invoices => _invoiceService ??= InvoiceService(
    httpClient: _httpClient,
    localDb: _localDb,
    syncQueue: _syncQueue,
    connectivityMonitor: _connectivityMonitor,
  );

  QuoteService get quotes => _quoteService ??= QuoteService(
    httpClient: _httpClient,
    localDb: _localDb,
    syncQueue: _syncQueue,
    connectivityMonitor: _connectivityMonitor,
  );

  InventoryService get inventory => _inventoryService ??= InventoryService(
    httpClient: _httpClient,
    localDb: _localDb,
    syncQueue: _syncQueue,
    connectivityMonitor: _connectivityMonitor,
  );

  ReportService get reports => _reportService ??= ReportService(
    httpClient: _httpClient,
    localDb: _localDb,
    connectivityMonitor: _connectivityMonitor,
  );

  /// The sync manager (null if offline is disabled).
  SyncManager? get sync => _syncManager;

  /// The sync event bus for observing status and connectivity changes.
  SyncEventBus? get events => _eventBus;

  /// Whether the device is currently online.
  bool get isOnline => _connectivityMonitor?.isOnline ?? true;

  /// Whether the SDK has been initialized.
  bool get isInitialized => _initialized;

  /// Whether offline storage is available.
  bool get isOfflineAvailable => _localDb != null;

  /// Whether the SDK currently holds a valid auth token.
  bool get isAuthenticated => _authManager.isAuthenticated;

  String? get accessToken => _authManager.accessToken;

  // ── Sync Convenience Methods ────────────────────────────

  /// Manually trigger a full sync cycle.
  Future<SyncStatus> syncNow() async {
    if (_syncManager == null) {
      throw StateError('Offline storage is not enabled. Set offlineEnabled: true in config.');
    }
    return _syncManager!.syncAll();
  }

  /// Get sync statistics for all entity types.
  Future<List<EntitySyncStats>> getSyncStats() async {
    if (_syncManager == null) return [];
    return _syncManager!.getStats();
  }

  /// Get the number of pending operations in the sync queue.
  Future<int> getPendingCount() async {
    if (_syncQueue == null) return 0;
    return _syncQueue!.pendingCount();
  }

  /// Enable or disable auto-sync.
  void setAutoSync(bool enabled) {
    _syncManager?.setAutoSync(enabled);
  }

  // ── Cleanup ─────────────────────────────────────────────

  /// Clear all local data (useful for logout).
  Future<void> clearLocalData() async {
    await _localDb?.clearAll();
  }

  /// Dispose of all resources.
  Future<void> dispose() async {
    _syncManager?.dispose();
    _httpClient.dispose();
    await _localDb?.close();
    _eventBus?.removeAllListeners();
    _initialized = false;
  }
}