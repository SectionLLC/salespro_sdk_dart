import 'package:uuid/uuid.dart';
import '../client/http_client.dart';
import '../storage/local_database.dart';
import '../storage/sync_queue.dart';
import '../storage/connectivity_monitor.dart';
import '../models/order.dart';
import '../models/api_response.dart';
import '../exceptions/sdk_exceptions.dart';

/// Offline-first service for Order CRUD operations.
class OrderService {
  static const String _basePath = '/orders';
  static const String _entityType = 'order';
  static const String _table = LocalDatabase.ordersTable;

  final SalesProHttpClient _httpClient;
  final LocalDatabase? _localDb;
  final SyncQueue? _syncQueue;
  final ConnectivityMonitor? _connectivityMonitor;
  final _uuid = const Uuid();

  OrderService({
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

  /// List orders with optional filters and pagination.
  ///
  /// When offline, returns locally stored orders.
  Future<ApiResponse> list({
    int? page,
    int? perPage,
    String? status,
    String? contactId,
    DateTime? dateFrom,
    DateTime? dateTo,
    Map<String, dynamic>? filters,
  }) async {
    final params = <String, dynamic>{
      if (page != null) 'page': page,
      if (perPage != null) 'per_page': perPage,
      if (status != null) 'status': status,
      if (contactId != null) 'contact_id': contactId,
      if (dateFrom != null) 'date_from': dateFrom.toIso8601String(),
      if (dateTo != null) 'date_to': dateTo.toIso8601String(),
      ...?filters,
    };

    // Try remote first
    if (_isOnline) {
      try {
        final response = await _httpClient.get(_basePath, queryParams: params);

        // Cache results locally
        if (_isOfflineAvailable && response.data != null) {
          await _cacheList(response.data);
        }

        return response;
      } on NetworkException {
        // Fall through to local storage
      } on SalesProException {
        rethrow;
      }
    }

    // Fallback to local storage
    if (_isOfflineAvailable) {
      return _localList(params);
    }

    throw NetworkException(
        message: 'No internet connection and offline storage is not available');
  }

  /// Get a single order by ID.
  Future<Order> get(String id) async {
    // Try remote first
    if (_isOnline) {
      try {
        final response = await _httpClient.get('$_basePath/$id');
        final order = Order.fromJson(response.data as Map<String, dynamic>);

        // Cache locally
        if (_isOfflineAvailable && order.id != null) {
          await _localDb!.upsertEntity(
              _table, order.id!, response.data as Map<String, dynamic>);
        }

        return order;
      } on NetworkException {
        // Fall through to local
      } on SalesProException {
        rethrow;
      }
    }

    // Fallback to local
    if (_isOfflineAvailable) {
      final data = await _localDb!.getEntity(_table, id);
      if (data != null) return Order.fromJson(data);
      throw NotFoundException(message: 'Order $id not found locally');
    }

    throw NetworkException(message: 'No internet connection');
  }

  /// Create a new order.
  ///
  /// Saves locally as dirty first, then pushes to server.
  /// If offline, the create is queued for auto-sync.
  Future<Order> create(Order order) async {
    // Assign a temporary local ID if none exists
    final localId = order.id ?? 'local_${_uuid.v4()}';
    final json = order.toJson();
    json['id'] = localId;

    // Save locally as dirty
    if (_isOfflineAvailable) {
      await _localDb!.upsertEntity(_table, localId, json, isDirty: true);
    }

    // Try remote
    if (_isOnline) {
      try {
        final response =
            await _httpClient.post(_basePath, body: order.toJson());
        final created = Order.fromJson(response.data as Map<String, dynamic>);

        // Replace local with server version
        if (_isOfflineAvailable && created.id != null) {
          await _localDb!.upsertEntity(
            _table,
            created.id!,
            response.data as Map<String, dynamic>,
          );
          // Remove the temp-local entry if IDs differ
          if (created.id != localId) {
            await _localDb!.deleteEntity(_table, localId);
          }
        }

        return created;
      } on NetworkException {
        // Queue for later sync
        _enqueue(localId, 'create', _basePath, json);
        return Order.fromJson(json);
      } on SalesProException {
        rethrow;
      }
    }

    // Offline — queue it
    _enqueue(localId, 'create', _basePath, json);
    return Order.fromJson(json);
  }

  /// Update an existing order.
  Future<Order> update(String id, Order order) async {
    final json = order.toJson();

    // Save locally as dirty
    if (_isOfflineAvailable) {
      await _localDb!.upsertEntity(_table, id, json, isDirty: true);
    }

    // Try remote
    if (_isOnline) {
      try {
        final response = await _httpClient.put('$_basePath/$id', body: json);
        final updated = Order.fromJson(response.data as Map<String, dynamic>);

        // Update local with clean server version
        if (_isOfflineAvailable) {
          await _localDb!.upsertEntity(
            _table,
            id,
            response.data as Map<String, dynamic>,
          );
        }

        return updated;
      } on NetworkException {
        _enqueue(id, 'update', '$_basePath/$id', json);
        return order;
      } on SalesProException {
        rethrow;
      }
    }

    // Offline — queue it
    _enqueue(id, 'update', '$_basePath/$id', json);
    return order;
  }

  /// Delete an order.
  Future<void> delete(String id) async {
    // Soft-delete locally
    if (_isOfflineAvailable) {
      await _localDb!.softDeleteEntity(_table, id);
    }

    // Try remote
    if (_isOnline) {
      try {
        await _httpClient.delete('$_basePath/$id');
        // Hard-delete locally since server confirmed
        if (_isOfflineAvailable) {
          await _localDb!.deleteEntity(_table, id);
        }
        return;
      } on NetworkException {
        // Queue the delete
      } on SalesProException {
        rethrow;
      }
    }

    // Offline — queue the delete
    _enqueue(id, 'delete', '$_basePath/$id');
  }

  /// Change order status (e.g. 'confirmed', 'shipped', 'delivered', 'cancelled').
  Future<Order> changeStatus(String id, String status) async {
    final body = {'status': status};

    // Apply locally first
    if (_isOfflineAvailable) {
      final existing = await _localDb!.getEntity(_table, id);
      if (existing != null) {
        final merged = {...existing, 'status': status};
        await _localDb!.upsertEntity(_table, id, merged, isDirty: true);
      }
    }

    // Try remote
    if (_isOnline) {
      try {
        final response =
            await _httpClient.patch('$_basePath/$id/status', body: body);
        final updated = Order.fromJson(response.data as Map<String, dynamic>);

        if (_isOfflineAvailable) {
          await _localDb!
              .upsertEntity(_table, id, response.data as Map<String, dynamic>);
        }

        return updated;
      } on NetworkException {
        _enqueue(id, 'patch', '$_basePath/$id', body);
      } on SalesProException {
        rethrow;
      }
    } else {
      _enqueue(id, 'patch', '$_basePath/$id', body);
    }

    // Return local state
    final data = await _localDb?.getEntity(_table, id);
    return Order.fromJson(data ?? body);
  }

  /// Convert a quote to an order.
  ///
  /// Note: Requires internet connection as it involves server-side generation logic.
  Future<Order> convertFromQuote(String quoteId) async {
    if (!_isOnline) {
      throw NetworkException(
          message: 'Cannot convert quote to order while offline');
    }

    final response = await _httpClient.post(
      '$_basePath/from-quote',
      body: {'quote_id': quoteId},
    );

    final order = Order.fromJson(response.data as Map<String, dynamic>);

    // Cache the newly created order locally
    if (_isOfflineAvailable && order.id != null) {
      await _localDb!.upsertEntity(
          _table, order.id!, response.data as Map<String, dynamic>);
    }

    return order;
  }

  /// Add a line item to an existing order.
  Future<Order> addLineItem(String orderId, OrderLineItem item) async {
    final body = item.toJson();

    // Optimistic local update: append the item to the local order's line_items
    if (_isOfflineAvailable) {
      final existing = await _localDb!.getEntity(_table, orderId);
      if (existing != null) {
        final order = Order.fromJson(existing);
        final items = [...?order.lineItems, item];
        final merged = order.toJson();
        merged['line_items'] = items.map((e) => e.toJson()).toList();
        await _localDb!.upsertEntity(_table, orderId, merged, isDirty: true);
      }
    }

    // Try remote
    if (_isOnline) {
      try {
        final response = await _httpClient.post(
          '$_basePath/$orderId/line-items',
          body: body,
        );
        final updated = Order.fromJson(response.data as Map<String, dynamic>);

        if (_isOfflineAvailable) {
          await _localDb!.upsertEntity(
              _table, orderId, response.data as Map<String, dynamic>);
        }

        return updated;
      } on NetworkException {
        _enqueue(
            orderId, 'patch', '$_basePath/$orderId', {'add_line_item': body});
      } on SalesProException {
        rethrow;
      }
    } else {
      _enqueue(
          orderId, 'patch', '$_basePath/$orderId', {'add_line_item': body});
    }

    // Return local state
    final data = await _localDb?.getEntity(_table, orderId);
    return Order.fromJson(data ?? {});
  }

  /// Remove a line item from an order.
  Future<Order> removeLineItem(String orderId, String lineItemId) async {
    // Optimistic local update: filter out the item from local order's line_items
    if (_isOfflineAvailable) {
      final existing = await _localDb!.getEntity(_table, orderId);
      if (existing != null) {
        final order = Order.fromJson(existing);
        final items =
            order.lineItems?.where((i) => i.id != lineItemId).toList() ?? [];
        final merged = order.toJson();
        merged['line_items'] = items.map((e) => e.toJson()).toList();
        await _localDb!.upsertEntity(_table, orderId, merged, isDirty: true);
      }
    }

    // Try remote
    if (_isOnline) {
      try {
        final response = await _httpClient.delete(
          '$_basePath/$orderId/line-items/$lineItemId',
        );
        final updated = Order.fromJson(response.data as Map<String, dynamic>);

        if (_isOfflineAvailable) {
          await _localDb!.upsertEntity(
              _table, orderId, response.data as Map<String, dynamic>);
        }

        return updated;
      } on NetworkException {
        _enqueue(orderId, 'patch', '$_basePath/$orderId',
            {'remove_line_item_id': lineItemId});
      } on SalesProException {
        rethrow;
      }
    } else {
      _enqueue(orderId, 'patch', '$_basePath/$orderId',
          {'remove_line_item_id': lineItemId});
    }

    // Return local state
    final data = await _localDb?.getEntity(_table, orderId);
    return Order.fromJson(data ?? {});
  }

  /// Calculate order totals (without persisting).
  ///
  /// Note: Requires internet connection as calculation is performed server-side.
  Future<Map<String, dynamic>> calculateTotals(Order order) async {
    if (!_isOnline) {
      throw NetworkException(message: 'Cannot calculate totals while offline');
    }

    final response = await _httpClient.post(
      '$_basePath/calculate',
      body: order.toJson(),
    );

    return response.data as Map<String, dynamic>;
  }

  // ── Private Helpers ──────────────────────────────────────

  void _enqueue(String entityId, String operation, String path,
      [Map<String, dynamic>? body]) {
    _syncQueue?.enqueue(
      entityType: _entityType,
      entityId: entityId,
      operation: operation,
      path: path,
      body: body,
    );
  }

  /// Cache a list response locally.
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

  /// Build an ApiResponse from local storage.
  Future<ApiResponse> _localList(Map<String, dynamic> params) async {
    final limit = (params['per_page'] as int?) ?? 25;
    final page = (params['page'] as int?) ?? 1;
    final offset = (page - 1) * limit;

    var entities =
        await _localDb!.getAllEntities(_table, limit: limit, offset: offset);

    // Apply basic local filters
    if (params['status'] != null) {
      entities =
          entities.where((e) => e['status'] == params['status']).toList();
    }
    if (params['contact_id'] != null) {
      entities = entities
          .where((e) => e['contact_id'] == params['contact_id'])
          .toList();
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
