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

    if (_isOnline) {
      try {
        final response = await _httpClient.get(_basePath, queryParams: params);
        if (_isOfflineAvailable && response.data != null) {
          _cacheList(response.data);
        }
        return response;
      } on NetworkException {} on SalesProException {
        rethrow;
      }
    }

    if (_isOfflineAvailable) return _localList(params);
    throw NetworkException(message: 'No internet connection');
  }

  Future<Order> get(String id) async {
    if (_isOnline) {
      try {
        final response = await _httpClient.get('$_basePath/$id');
        final order = Order.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable && order.id != null) {
          await _localDb!.upsertEntity(_table, order.id!, response.data as Map<String, dynamic>);
        }
        return order;
      } on NetworkException {} on SalesProException {
        rethrow;
      }
    }

    if (_isOfflineAvailable) {
      final data = await _localDb!.getEntity(_table, id);
      if (data != null) return Order.fromJson(data);
      throw NotFoundException(message: 'Order $id not found locally');
    }

    throw NetworkException(message: 'No internet connection');
  }

  Future<Order> create(Order order) async {
    final localId = order.id ?? 'local_${_uuid.v4()}';
    final json = order.toJson();
    json['id'] = localId;

    if (_isOfflineAvailable) {
      await _localDb!.upsertEntity(_table, localId, json, isDirty: true);
    }

    if (_isOnline) {
      try {
        final response = await _httpClient.post(_basePath, body: order.toJson());
        final created = Order.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable && created.id != null) {
          await _localDb!.upsertEntity(_table, created.id!, response.data as Map<String, dynamic>);
          if (created.id != localId) await _localDb!.deleteEntity(_table, localId);
        }
        return created;
      } on NetworkException {
        if (_syncQueue != null) {
          await _syncQueue!.enqueue(
            entityType: _entityType, entityId: localId,
            operation: 'create', path: _basePath, body: json,
          );
        }
        return Order.fromJson(json);
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
    return Order.fromJson(json);
  }

  Future<Order> update(String id, Order order) async {
    final json = order.toJson();
    if (_isOfflineAvailable) {
      await _localDb!.upsertEntity(_table, id, json, isDirty: true);
    }

    if (_isOnline) {
      try {
        final response = await _httpClient.put('$_basePath/$id', body: json);
        final updated = Order.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable) {
          await _localDb!.upsertEntity(_table, id, response.data as Map<String, dynamic>);
        }
        return updated;
      } on NetworkException {
        _enqueueUpdate(id, json);
        return order;
      } on SalesProException {
        rethrow;
      }
    }

    _enqueueUpdate(id, json);
    return order;
  }

  Future<void> delete(String id) async {
    if (_isOfflineAvailable) await _localDb!.softDeleteEntity(_table, id);

    if (_isOnline) {
      try {
        await _httpClient.delete('$_basePath/$id');
        if (_isOfflineAvailable) await _localDb!.deleteEntity(_table, id);
        return;
      } on NetworkException {} on SalesProException {
        rethrow;
      }
    }

    _enqueueDelete(id);
  }

  Future<Order> changeStatus(String id, String status) async {
    final body = {'status': status};

    if (_isOfflineAvailable) {
      final existing = await _localDb!.getEntity(_table, id);
      if (existing != null) {
        final merged = {...existing, 'status': status};
        await _localDb!.upsertEntity(_table, id, merged, isDirty: true);
      }
    }

    if (_isOnline) {
      try {
        final response = await _httpClient.patch('$_basePath/$id/status', body: body);
        final updated = Order.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable) {
          await _localDb!.upsertEntity(_table, id, response.data as Map<String, dynamic>);
        }
        return updated;
      } on NetworkException {
        _enqueuePatch(id, body);
      } on SalesProException {
        rethrow;
      }
    } else {
      _enqueuePatch(id, body);
    }

    final data = await _localDb?.getEntity(_table, id);
    return Order.fromJson(data ?? body);
  }

  Future<Order> convertFromQuote(String quoteId) async {
    if (!_isOnline) throw NetworkException(message: 'Cannot convert quote offline');
    final response = await _httpClient.post('$_basePath/from-quote', body: {'quote_id': quoteId});
    final order = Order.fromJson(response.data as Map<String, dynamic>);
    if (_isOfflineAvailable && order.id != null) {
      await _localDb!.upsertEntity(_table, order.id!, response.data as Map<String, dynamic>);
    }
    return order;
  }

  Future<Order> addLineItem(String orderId, OrderLineItem item) async {
    final body = item.toJson();

    if (_isOfflineAvailable) {
      final existing = await _localDb!.getEntity(_table, orderId);
      if (existing != null) {
        final order = Order.fromJson(existing);
        final items = [...?order.lineItems, item];
        final merged = order.copyWith().toJson();
        merged['line_items'] = items.map((e) => e.toJson()).toList();
        await _localDb!.upsertEntity(_table, orderId, merged, isDirty: true);
      }
    }

    if (_isOnline) {
      try {
        final response = await _httpClient.post('$_basePath/$orderId/line-items', body: body);
        final updated = Order.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable) {
          await _localDb!.upsertEntity(_table, orderId, response.data as Map<String, dynamic>);
        }
        return updated;
      } on NetworkException {
        _enqueuePatch(orderId, {'add_line_item': body});
      } on SalesProException {
        rethrow;
      }
    } else {
      _enqueuePatch(orderId, {'add_line_item': body});
    }

    final data = await _localDb?.getEntity(_table, orderId);
    return Order.fromJson(data ?? {});
  }

  Future<Order> removeLineItem(String orderId, String lineItemId) async {
    if (_isOnline) {
      final response = await _httpClient.delete('$_basePath/$orderId/line-items/$lineItemId');
      final updated = Order.fromJson(response.data as Map<String, dynamic>);
      if (_isOfflineAvailable) {
        await _localDb!.upsertEntity(_table, orderId, response.data as Map<String, dynamic>);
      }
      return updated;
    }
    throw NetworkException(message: 'Cannot remove line item offline');
  }

  Future<Map<String, dynamic>> calculateTotals(Order order) async {
    if (!_isOnline) throw NetworkException(message: 'Cannot calculate totals offline');
    final response = await _httpClient.post('$_basePath/calculate', body: order.toJson());
    return response.data as Map<String, dynamic>;
  }

  // ── Helpers ──────────────────────────────────────────────

  void _enqueueUpdate(String id, Map<String, dynamic> json) {
    _syncQueue?.enqueue(
      entityType: _entityType, entityId: id,
      operation: 'update', path: '$_basePath/$id', body: json,
    );
  }

  void _enqueueDelete(String id) {
    _syncQueue?.enqueue(
      entityType: _entityType, entityId: id,
      operation: 'delete', path: '$_basePath/$id',
    );
  }

  void _enqueuePatch(String id, Map<String, dynamic> body) {
    _syncQueue?.enqueue(
      entityType: _entityType, entityId: id,
      operation: 'patch', path: '