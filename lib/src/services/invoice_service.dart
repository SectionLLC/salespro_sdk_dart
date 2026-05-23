import 'package:uuid/uuid.dart';
import '../client/http_client.dart';
import '../storage/local_database.dart';
import '../storage/sync_queue.dart';
import '../storage/connectivity_monitor.dart';
import '../models/invoice.dart';
import '../models/api_response.dart';
import '../exceptions/sdk_exceptions.dart';

class InvoiceService {
  static const String _basePath = '/invoices';
  static const String _entityType = 'invoice';
  static const String _table = LocalDatabase.invoicesTable;

  final SalesProHttpClient _httpClient;
  final LocalDatabase? _localDb;
  final SyncQueue? _syncQueue;
  final ConnectivityMonitor? _connectivityMonitor;
  final _uuid = const Uuid();

  InvoiceService({
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
    int? page, int? perPage, String? status, String? contactId,
    DateTime? dateFrom, DateTime? dateTo, Map<String, dynamic>? filters,
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
      } on NetworkException {} on SalesProException { rethrow; }
    }

    if (_isOfflineAvailable) return _localList(params);
    throw NetworkException(message: 'No internet connection');
  }

  Future<Invoice> get(String id) async {
    if (_isOnline) {
      try {
        final response = await _httpClient.get('$_basePath/$id');
        final invoice = Invoice.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable && invoice.id != null) {
          await _localDb!.upsertEntity(_table, invoice.id!, response.data as Map<String, dynamic>);
        }
        return invoice;
      } on NetworkException {} on SalesProException { rethrow; }
    }

    if (_isOfflineAvailable) {
      final data = await _localDb!.getEntity(_table, id);
      if (data != null) return Invoice.fromJson(data);
      throw NotFoundException(message: 'Invoice $id not found locally');
    }
    throw NetworkException(message: 'No internet connection');
  }

  Future<Invoice> create(Invoice invoice) async {
    final localId = invoice.id ?? 'local_${_uuid.v4()}';
    final json = invoice.toJson();
    json['id'] = localId;

    if (_isOfflineAvailable) {
      await _localDb!.upsertEntity(_table, localId, json, isDirty: true);
    }

    if (_isOnline) {
      try {
        final response = await _httpClient.post(_basePath, body: invoice.toJson());
        final created = Invoice.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable && created.id != null) {
          await _localDb!.upsertEntity(_table, created.id!, response.data as Map<String, dynamic>);
          if (created.id != localId) await _localDb!.deleteEntity(_table, localId);
        }
        return created;
      } on NetworkException {
        _enqueue(localId, 'create', _basePath, json);
        return Invoice.fromJson(json);
      } on SalesProException { rethrow; }
    }

    _enqueue(localId, 'create', _basePath, json);
    return Invoice.fromJson(json);
  }

  Future<Invoice> createFromOrder(String orderId) async {
    if (!_isOnline) throw NetworkException(message: 'Cannot create invoice from order offline');
    final response = await _httpClient.post('$_basePath/from-order', body: {'order_id': orderId});
    final invoice = Invoice.fromJson(response.data as Map<String, dynamic>);
    if (_isOfflineAvailable && invoice.id != null) {
      await _localDb!.upsertEntity(_table, invoice.id!, response.data as Map<String, dynamic>);
    }
    return invoice;
  }

  Future<Invoice> update(String id, Invoice invoice) async {
    final json = invoice.toJson();
    if (_isOfflineAvailable) {
      await _localDb!.upsertEntity(_table, id, json, isDirty: true);
    }

    if (_isOnline) {
      try {
        final response = await _httpClient.put('$_basePath/$id', body: json);
        final updated = Invoice.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable) {
          await _localDb!.upsertEntity(_table, id, response.data as Map<String, dynamic>);
        }
        return updated;
      } on NetworkException {
        _enqueue(id, 'update', '$_basePath/$id', json);
        return invoice;
      } on SalesProException { rethrow; }
    }

    _enqueue(id, 'update', '$_basePath/$id', json);
    return invoice;
  }

  Future<void> delete(String id) async {
    if (_isOfflineAvailable) await _localDb!.softDeleteEntity(_table, id);
    if (_isOnline) {
      try {
        await _httpClient.delete('$_basePath/$id');
        if (_isOfflineAvailable) await _localDb!.deleteEntity(_table, id);
        return;
      } on NetworkException {} on SalesProException { rethrow; }
    }
    _enqueue(id, 'delete', '$_basePath/$id');
  }

  Future<Invoice> changeStatus(String id, String status) async {
    final body = {'status': status};
    if (_isOfflineAvailable) {
      final existing = await _localDb!.getEntity(_table, id);
      if (existing != null) {
        await _localDb!.upsertEntity(_table, id, {...existing, 'status': status}, isDirty: true);
      }
    }

    if (_isOnline) {
      try {
        final response = await _httpClient.patch('$_basePath/$id/status', body: body);
        final updated = Invoice.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable) {
          await _localDb!.upsertEntity(_table, id, response.data as Map<String, dynamic>);
        }
        return updated;
      } on NetworkException { _enqueue(id, 'patch', '$_basePath/$id', body); }
        on SalesProException { rethrow; }
    } else {
      _enqueue(id, 'patch', '$_basePath/$id', body);
    }

    final data = await _localDb?.getEntity(_table, id);
    return Invoice.fromJson(data ?? body);
  }

  Future<Invoice> recordPayment(String id, {
    required double amount, String? paymentMethod, String? reference, DateTime? paymentDate,
  }) async {
    final body = {
      'amount': amount,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (reference != null) 'reference': reference,
      if (paymentDate != null) 'payment_date': paymentDate.toIso8601String(),
    };

    if (_isOfflineAvailable) {
      final existing = await _localDb!.getEntity(_table, id);
      if (existing != null) {
        final currentPaid = (existing['amount_paid'] as num?)?.toDouble() ?? 0;
        final currentDue = (existing['amount_due'] as num?)?.toDouble() ?? 0;
        final merged = {
          ...existing,
          'amount_paid': currentPaid + amount,
          'amount_due': (currentDue - amount).clamp(0, double.infinity),
        };
        if (merged['amount_due'] == 0) merged['status'] = 'paid';
        await _localDb!.upsertEntity(_table, id, merged, isDirty: true);
      }
    }

    if (_isOnline) {
      try {
        final response = await _httpClient.post('$_basePath/$id/payments', body: body);
        final updated = Invoice.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable) {
          await _localDb!.upsertEntity(_table, id, response.data as Map<String, dynamic>);
        }
        return updated;
      } on NetworkException { _enqueue(id, 'patch', '$_basePath/$id', body); }
        on SalesProException { rethrow; }
    } else {
      _enqueue(id, 'patch', '$_basePath/$id', body);
    }

    final data = await _localDb?.getEntity(_table, id);
    return Invoice.fromJson(data ?? body);
  }

  Future<void> send(String id, {String? email}) async {
    if (!_isOnline) throw NetworkException(message: 'Cannot send invoice offline');
    await _httpClient.post('$_basePath/$id/send', body: {if (email != null) 'email': email});
  }

  Future<List<int>> downloadPdf(String id) async {
    if (!_isOnline) throw NetworkException(message: 'Cannot download PDF offline');
    final response = await _httpClient.get('$_basePath/$id/pdf');
    if (response.data is String) {
      return Uri.parse('data:application/pdf;base64,${response.data}').data!.contentAsBytes();
    }
    return [];
  }

  void _enqueue(String entityId, String operation, String path, [Map<String, dynamic>? body]) {
    _syncQueue?.enqueue(
      entityType: _entityType, entityId: entityId,
      operation: operation, path: path, body: body,
    );
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

    if (params['status'] != null) {
      entities = entities.where((e) => e['status'] == params['status']).toList();
    }
    if (params['contact_id'] != null) {
      entities = entities.where((e) => e['contact_id'] == params['contact_id']).toList();
    }

    final totalCount = await _localDb!.countEntities(_table);

    return ApiResponse(
      success: true, statusCode: 200,
      data: {
        'data': entities,
        'pagination': {
          'current_page': page,
          'total_pages': (totalCount / limit).ceil(),
          'total': totalCount, 'per_page': limit,
        },
      },
      message: 'Loaded from local storage',
    );
  }
}