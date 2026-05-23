import 'package:uuid/uuid.dart';
import '../client/http_client.dart';
import '../storage/local_database.dart';
import '../storage/sync_queue.dart';
import '../storage/connectivity_monitor.dart';
import '../models/quote.dart';
import '../models/api_response.dart';
import '../exceptions/sdk_exceptions.dart';

class QuoteService {
  static const String _basePath = '/quotes';
  static const String _entityType = 'quote';
  static const String _table = LocalDatabase.quotesTable;

  final SalesProHttpClient _httpClient;
  final LocalDatabase? _localDb;
  final SyncQueue? _syncQueue;
  final ConnectivityMonitor? _connectivityMonitor;
  final _uuid = const Uuid();

  QuoteService({
    required SalesProHttpClient httpClient,
    LocalDatabase? localDb, SyncQueue? syncQueue,
    ConnectivityMonitor? connectivityMonitor,
  })  : _httpClient = httpClient, _localDb = localDb,
        _syncQueue = syncQueue, _connectivityMonitor = connectivityMonitor;

  bool get _isOfflineAvailable => _localDb != null;
  bool get _isOnline => _connectivityMonitor?.isOnline ?? true;

  Future<ApiResponse> list({
    int? page, int? perPage, String? status, String? contactId,
    Map<String, dynamic>? filters,
  }) async {
    final params = <String, dynamic>{
      if (page != null) 'page': page,
      if (perPage != null) 'per_page': perPage,
      if (status != null) 'status': status,
      if (contactId != null) 'contact_id': contactId,
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

  Future<Quote> get(String id) async {
    if (_isOnline) {
      try {
        final response = await _httpClient.get('$_basePath/$id');
        final quote = Quote.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable && quote.id != null) {
          await _localDb!.upsertEntity(_table, quote.id!, response.data as Map<String, dynamic>);
        }
        return quote;
      } on NetworkException {} on SalesProException { rethrow; }
    }

    if (_isOfflineAvailable) {
      final data = await _localDb!.getEntity(_table, id);
      if (data != null) return Quote.fromJson(data);
      throw NotFoundException(message: 'Quote $id not found locally');
    }
    throw NetworkException(message: 'No internet connection');
  }

  Future<Quote> create(Quote quote) async {
    final localId = quote.id ?? 'local_${_uuid.v4()}';
    final json = quote.toJson();
    json['id'] = localId;

    if (_isOfflineAvailable) {
      await _localDb!.upsertEntity(_table, localId, json, isDirty: true);
    }

    if (_isOnline) {
      try {
        final response = await _httpClient.post(_basePath, body: quote.toJson());
        final created = Quote.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable && created.id != null) {
          await _localDb!.upsertEntity(_table, created.id!, response.data as Map<String, dynamic>);
          if (created.id != localId) await _localDb!.deleteEntity(_table, localId);
        }
        return created;
      } on NetworkException { _enqueue(localId, 'create', _basePath, json); return Quote.fromJson(json); }
        on SalesProException { rethrow; }
    }

    _enqueue(localId, 'create', _basePath, json);
    return Quote.fromJson(json);
  }

  Future<Quote> update(String id, Quote quote) async {
    final json = quote.toJson();
    if (_isOfflineAvailable) await _localDb!.upsertEntity(_table, id, json, isDirty: true);

    if (_isOnline) {
      try {
        final response = await _httpClient.put('$_basePath/$id', body: json);
        final updated = Quote.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable) await _localDb!.upsertEntity(_table, id, response.data as Map<String, dynamic>);
        return updated;
      } on NetworkException { _enqueue(id, 'update', '$_basePath/$id', json); return quote; }
        on SalesProException { rethrow; }
    }

    _enqueue(id, 'update', '$_basePath/$id', json);
    return quote;
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

  Future<Quote> changeStatus(String id, String status) async {
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
        final updated = Quote.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable) await _localDb!.upsertEntity(_table, id, response.data as Map<String, dynamic>);
        return updated;
      } on NetworkException { _enqueue(id, 'patch', '$_basePath/$id', body); }
        on SalesProException { rethrow; }
    } else { _enqueue(id, 'patch', '$_basePath/$id', body); }

    final data = await _localDb?.getEntity(_table, id);
    return Quote.fromJson(data ?? body);
  }

  Future<void> send(String id, {String? email}) async {
    if (!_isOnline) throw NetworkException(message: 'Cannot send quote offline');
    await _httpClient.post('$_basePath/$id/send', body: {if (email != null) 'email': email});
  }

  Future<Map<String, dynamic>> convertToOrder(String id) async {
    if (!_isOnline) throw NetworkException(message: 'Cannot convert quote offline');
    final response = await _httpClient.post('$_basePath/$id/convert');
    return response.data as Map<String, dynamic>;
  }

  void _enqueue(String entityId, String operation, String path, [Map<String, dynamic>? body]) {
    _syncQueue?.enqueue(entityType: _entityType, entityId: entityId, operation: operation, path: path, body: body);
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

    if (params['status'] != null) entities = entities.where((e) => e['status'] == params['status']).toList();
    if (params['contact_id'] != null) entities = entities.where((e) => e['contact_id'] == params['contact_id']).toList();

    final totalCount = await _localDb!.countEntities(_table);
    return ApiResponse(success: true, statusCode: 200, data: {
      'data': entities,
      'pagination': {'current_page': page, 'total_pages': (totalCount / limit).ceil(), 'total': totalCount, 'per_page': limit},
    }, message: 'Loaded from local storage');
  }
}