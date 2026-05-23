import '../client/http_client.dart';
import '../storage/local_database.dart';
import '../storage/sync_queue.dart';
import '../storage/connectivity_monitor.dart';
import '../models/inventory_item.dart';
import '../models/api_response.dart';
import '../exceptions/sdk_exceptions.dart';

class InventoryService {
  static const String _basePath = '/inventory';
  static const String _entityType = 'inventory_item';
  static const String _table = LocalDatabase.inventoryTable;

  final SalesProHttpClient _httpClient;
  final LocalDatabase? _localDb;
  final SyncQueue? _syncQueue;
  final ConnectivityMonitor? _connectivityMonitor;

  InventoryService({
    required SalesProHttpClient httpClient,
    LocalDatabase? localDb, SyncQueue? syncQueue,
    ConnectivityMonitor? connectivityMonitor,
  })  : _httpClient = httpClient, _localDb = localDb,
        _syncQueue = syncQueue, _connectivityMonitor = connectivityMonitor;

  bool get _isOfflineAvailable => _localDb != null;
  bool get _isOnline => _connectivityMonitor?.isOnline ?? true;

  Future<ApiResponse> list({
    int? page, int? perPage, String? warehouse, bool? lowStock,
    String? sku, Map<String, dynamic>? filters,
  }) async {
    final params = <String, dynamic>{
      if (page != null) 'page': page,
      if (perPage != null) 'per_page': perPage,
      if (warehouse != null) 'warehouse': warehouse,
      if (lowStock != null) 'low_stock': lowStock,
      if (sku != null) 'sku': sku,
      ...?filters,
    };

    if (_isOnline) {
      try {
        final response = await _httpClient.get(_basePath, queryParams: params);
        if (_isOfflineAvailable && response.data != null) _cacheList(response.data);
        return response;
      } on NetworkException {} on SalesProException { rethrow; }
    }

    if (_isOfflineAvailable) return _localList(params);
    throw NetworkException(message: 'No internet connection');
  }

  Future<InventoryItem> get(String productId) async {
    if (_isOnline) {
      try {
        final response = await _httpClient.get('$_basePath/$productId');
        final item = InventoryItem.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable && item.id != null) {
          await _localDb!.upsertEntity(_table, item.id!, response.data as Map<String, dynamic>);
        }
        return item;
      } on NetworkException {} on SalesProException { rethrow; }
    }

    if (_isOfflineAvailable) {
      final data = await _localDb!.getEntity(_table, productId);
      if (data != null) return InventoryItem.fromJson(data);
      throw NotFoundException(message: 'Inventory item $productId not found locally');
    }
    throw NetworkException(message: 'No internet connection');
  }

  Future<InventoryItem> adjust({
    required String productId, required int quantity,
    required String reason, String? warehouse, String? reference,
  }) async {
    final body = {
      'product_id': productId, 'quantity': quantity, 'reason': reason,
      if (warehouse != null) 'warehouse': warehouse,
      if (reference != null) 'reference': reference,
    };

    // Optimistic local update
    if (_isOfflineAvailable) {
      final existing = await _localDb!.getEntity(_table, productId);
      if (existing != null) {
        final currentQty = (existing['quantity_on_hand'] as num?)?.toInt() ?? 0;
        final merged = {...existing, 'quantity_on_hand': currentQty + quantity};
        await _localDb!.upsertEntity(_table, productId, merged, isDirty: true);
      }
    }

    if (_isOnline) {
      try {
        final response = await _httpClient.post('$_basePath/adjust', body: body);
        final updated = InventoryItem.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable && updated.id != null) {
          await _localDb!.upsertEntity(_table, updated.id!, response.data as Map<String, dynamic>);
        }
        return updated;
      } on NetworkException {
        _syncQueue?.enqueue(entityType: _entityType, entityId: productId, operation: 'patch', path: '$_basePath/adjust', body: body);
      } on SalesProException { rethrow; }
    } else {
      _syncQueue?.enqueue(entityType: _entityType, entityId: productId, operation: 'patch', path: '$_basePath/adjust', body: body);
    }

    final data = await _localDb?.getEntity(_table, productId);
    return InventoryItem.fromJson(data ?? body);
  }

  Future<ApiResponse> transfer({
    required String productId, required int quantity,
    required String fromWarehouse, required String toWarehouse,
  }) async {
    if (!_isOnline) throw NetworkException(message: 'Cannot transfer inventory offline');
    return _httpClient.post('$_basePath/transfer', body: {
      'product_id': productId, 'quantity': quantity,
      'from_warehouse': fromWarehouse, 'to_warehouse': toWarehouse,
    });
  }

  Future<ApiResponse> lowStock({int? page, int? perPage}) async {
    return list(lowStock: true, page: page, perPage: perPage);
  }

  Future<ApiResponse> warehouses() async {
    return _httpClient.get('/warehouses');
  }

  Future<ApiResponse> history(String productId, {int? page, int? perPage}) async {
    return _httpClient.get('$_basePath/$productId/history', queryParams: {
      if (page != null) 'page': page, if (perPage != null) 'per_page': perPage,
    });
  }

  Future<void> _cacheList(dynamic data) async {
    if (data is! Map) return;
    final items = data['items'] ?? data['data'] ?? data['results'];
    if (items is! List) return;
    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final id = map['id']?.toString();
      if (id != null) await _localDb!.upsertEntity(_table, id, map);
    }
  }

  Future<ApiResponse> _localList(Map<String, dynamic> params) async {
    final limit = (params['per_page'] as int?) ?? 25;
    final page = (params['page'] as int?) ?? 1;
    final offset = (page - 1) * limit;
    var entities = await _localDb!.getAllEntities(_table, limit: limit, offset: offset);

    if (params['warehouse'] != null) entities = entities.where((e) => e['warehouse'] == params['warehouse']).toList();
    if (params['low_stock'] == true) {
      entities = entities.where((e) {
        final qty = (e['quantity_on_hand'] as num?)?.toInt() ?? 0;
        final reorder = (e['reorder_point'] as num?)?.toInt() ?? 0;
        return qty <= reorder;
      }).toList();
    }

    final totalCount = await _localDb!.countEntities(_table);
    return ApiResponse(success: true, statusCode: 200, data: {
      'data': entities,
      'pagination': {'current_page': page, 'total_pages': (totalCount / limit).ceil(), 'total': totalCount, 'per_page': limit},
    }, message: 'Loaded from local storage');
  }
}