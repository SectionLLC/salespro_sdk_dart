import 'package:uuid/uuid.dart';
import '../client/http_client.dart';
import '../storage/local_database.dart';
import '../storage/sync_queue.dart';
import '../storage/connectivity_monitor.dart';
import '../models/product.dart';
import '../models/api_response.dart';
import '../exceptions/sdk_exceptions.dart';

/// Offline-first service for Product CRUD operations.
class ProductService {
  static const String _basePath = '/products';
  static const String _entityType = 'product';
  static const String _table = LocalDatabase.productsTable;

  final SalesProHttpClient _httpClient;
  final LocalDatabase? _localDb;
  final SyncQueue? _syncQueue;
  final ConnectivityMonitor? _connectivityMonitor;
  final _uuid = const Uuid();

  ProductService({
    required SalesProHttpClient httpClient,
    LocalDatabase? localDb,
    SyncQueue? syncQueue,
    ConnectivityMonitor? connectivityMonitor,
  })  : _httpClient = httpClient,
        _localDb = localDb,
        _syncQueue = syncQueue,
        _connectivityMonitor = connectivityMonitor;

  bool get _isOfflineAvailable => _localDb != null;
  bool get _isOnline => _connectivityMonitor?.isOnline ?? true;

  Future<ApiResponse> list({
    int? page,
    int? perPage,
    String? search,
    String? category,
    bool? isActive,
    Map<String, dynamic>? filters,
    String? sort,
  }) async {
    final params = <String, dynamic>{
      if (page != null) 'page': page,
      if (perPage != null) 'per_page': perPage,
      if (search != null) 'search': search,
      if (category != null) 'category': category,
      if (isActive != null) 'is_active': isActive,
      if (sort != null) 'sort': sort,
      ...?filters,
    };

    if (_isOnline) {
      try {
        final response = await _httpClient.get(_basePath, queryParams: params);
        if (_isOfflineAvailable && response.data != null) {
          await _cacheList(response.data);
        }
        return response;
      } on NetworkException {
        // Fall through to local
      } on SalesProException {
        rethrow;
      }
    }

    if (_isOfflineAvailable) {
      return _localList(params);
    }

    throw NetworkException(message: 'No internet connection');
  }

  Future<Product> get(String id) async {
    if (_isOnline) {
      try {
        final response = await _httpClient.get('$_basePath/$id');
        final product = Product.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable && product.id != null) {
          await _localDb!.upsertEntity(_table, product.id!, response.data as Map<String, dynamic>);
        }
        return product;
      } on NetworkException {} on SalesProException {
        rethrow;
      }
    }

    if (_isOfflineAvailable) {
      final data = await _localDb!.getEntity(_table, id);
      if (data != null) return Product.fromJson(data);
      throw NotFoundException(message: 'Product $id not found locally');
    }

    throw NetworkException(message: 'No internet connection');
  }

  Future<Product> getBySku(String sku) async {
    if (_isOnline) {
      try {
        final response = await _httpClient.get('$_basePath/sku/$sku');
        final product = Product.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable && product.id != null) {
          await _localDb!.upsertEntity(_table, product.id!, response.data as Map<String, dynamic>);
        }
        return product;
      } on NetworkException {} on SalesProException {
        rethrow;
      }
    }

    // Fallback: search local by SKU
    if (_isOfflineAvailable) {
      final all = await _localDb!.getAllEntities(_table);
      final match = all.where((e) => e['sku'] == sku || e['item_code'] == sku);
      if (match.isNotEmpty) return Product.fromJson(match.first);
      throw NotFoundException(message: 'Product with SKU $sku not found locally');
    }

    throw NetworkException(message: 'No internet connection');
  }

  Future<Product> create(Product product) async {
    final localId = product.id ?? 'local_${_uuid.v4()}';
    final productWithId = product.copyWith(id: localId);
    final json = productWithId.toJson();

    if (_isOfflineAvailable) {
      await _localDb!.upsertEntity(_table, localId, json, isDirty: true);
    }

    if (_isOnline) {
      try {
        final response = await _httpClient.post(_basePath, body: json);
        final created = Product.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable && created.id != null) {
          await _localDb!.upsertEntity(_table, created.id!, response.data as Map<String, dynamic>);
          if (created.id != localId) {
            await _localDb!.deleteEntity(_table, localId);
          }
        }
        return created;
      } on NetworkException {
        if (_syncQueue != null) {
          await _syncQueue!.enqueue(
            entityType: _entityType, entityId: localId,
            operation: 'create', path: _basePath, body: json,
          );
        }
        return productWithId;
      } on SalesProException {
        rethrow;
      }
    }

    if (_syncQueue != null) {
      await _syncQueue!.enqueue(
        entityType: _entityType, entityId: localId,
        operation: 'create', path: _basePath, body: json,
      );
    }
    return productWithId;
  }

  Future<Product> update(String id, Product product) async {
    final json = product.toJson();

    if (_isOfflineAvailable) {
      await _localDb!.upsertEntity(_table, id, json, isDirty: true);
    }

    if (_isOnline) {
      try {
        final response = await _httpClient.put('$_basePath/$id', body: json);
        final updated = Product.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable) {
          await _localDb!.upsertEntity(_table, id, response.data as Map<String, dynamic>);
        }
        return updated;
      } on NetworkException {
        if (_syncQueue != null) {
          await _syncQueue!.enqueue(
            entityType: _entityType, entityId: id,
            operation: 'update', path: '$_basePath/$id', body: json,
          );
        }
        return product;
      } on SalesProException {
        rethrow;
      }
    }

    if (_syncQueue != null) {
      await _syncQueue!.enqueue(
        entityType: _entityType, entityId: id,
        operation: 'update', path: '$_basePath/$id', body: json,
      );
    }
    return product;
  }

  Future<Product> patch(String id, Map<String, dynamic> fields) async {
    if (_isOfflineAvailable) {
      final existing = await _localDb!.getEntity(_table, id);
      if (existing != null) {
        final merged = {...existing, ...fields};
        await _localDb!.upsertEntity(_table, id, merged, isDirty: true);
      }
    }

    if (_isOnline) {
      try {
        final response = await _httpClient.patch('$_basePath/$id', body: fields);
        final updated = Product.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable) {
          await _localDb!.upsertEntity(_table, id, response.data as Map<String, dynamic>);
        }
        return updated;
      } on NetworkException {
        if (_syncQueue != null) {
          await _syncQueue!.enqueue(
            entityType: _entityType, entityId: id,
            operation: 'patch', path: '$_basePath/$id', body: fields,
          );
        }
        final data = await _localDb?.getEntity(_table, id);
        return Product.fromJson(data ?? fields);
      } on SalesProException {
        rethrow;
      }
    }

    if (_syncQueue != null) {
      await _syncQueue!.enqueue(
        entityType: _entityType, entityId: id,
        operation: 'patch', path: '$_basePath/$id', body: fields,
      );
    }
    final data = await _localDb?.getEntity(_table, id);
    return Product.fromJson(data ?? fields);
  }

  Future<void> delete(String id) async {
    if (_isOfflineAvailable) {
      await _localDb!.softDeleteEntity(_table, id);
    }

    if (_isOnline) {
      try {
        await _httpClient.delete('$_basePath/$id');
        if (_isOfflineAvailable) {
          await _localDb!.deleteEntity(_table, id);
        }
        return;
      } on NetworkException {} on SalesProException {
        rethrow;
      }
    }

    if (_syncQueue != null) {
      await _syncQueue!.enqueue(
        entityType: _entityType, entityId: id,
        operation: 'delete', path: '$_basePath/$id',
      );
    }
  }

  Future<ApiResponse> bulkUpdatePrices(Map<String, double> priceMap) async {
    return _httpClient.post('$_basePath/bulk/prices', body: {'prices': priceMap});
  }

  Future<ApiResponse> categories() async {
    return _httpClient.get('/product-categories');
  }

  Future<void> _cacheList(dynamic data) async {
    if (data is! Map) return;
    final items = data['items'] ?? data['data'] ?? data['results'];
    if (items is! List) return;
    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final id = map['id']?.toString();
      if (id != null) {
        await _localDb!.upsertEntity(_table, id, map);
      }
    }
  }

  Future<ApiResponse> _localList(Map<String, dynamic> params) async {
    final limit = (params['per_page'] as int?) ?? 25;
    final page = (params['page'] as int?) ?? 1;
    final offset = (page - 1) * limit;

    var entities = await _localDb!.getAllEntities(_table, limit: limit, offset: offset);

    if (params['search'] != null) {
      final q = params['search'].toString().toLowerCase();
      entities = entities.where((e) =>
        (e['name'] ?? '').toString().toLowerCase().contains(q) ||
        (e['sku'] ?? '').toString().toLowerCase().contains(q)
      ).toList();
    }

    if (params['category'] != null) {
      entities = entities.where((e) =>
        e['category'] == params['category'] || e['category_name'] == params['category']
      ).toList();
    }

    final totalCount = await _localDb!.countEntities(_table);

    return ApiResponse(
      success: true,
      statusCode: 200,
      data: {
        'data': entities,
        'pagination': {
          'current_page': page,
          'total_pages': (totalCount / limit).ceil(),
          'total': totalCount,
          'per_page': limit,
        },
      },
      message: 'Loaded from local storage',
    );
  }
}