import 'package:uuid/uuid.dart';
import '../client/http_client.dart';
import '../storage/local_database.dart';
import '../storage/sync_queue.dart';
import '../storage/connectivity_monitor.dart';
import '../models/contact.dart';
import '../models/api_response.dart';
import '../exceptions/sdk_exceptions.dart';

/// Offline-first service for Contact CRUD operations.
class ContactService {
  static const String _basePath = '/contacts';
  static const String _entityType = 'contact';
  static const String _table = LocalDatabase.contactsTable;

  final SalesProHttpClient _httpClient;
  final LocalDatabase? _localDb;
  final SyncQueue? _syncQueue;
  final ConnectivityMonitor? _connectivityMonitor;
  final _uuid = const Uuid();

  ContactService({
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

  /// List contacts with optional filters and pagination.
  ///
  /// When offline, returns locally stored contacts.
  Future<ApiResponse> list({
    int? page,
    int? perPage,
    String? search,
    Map<String, dynamic>? filters,
    String? sort,
    String? sortDirection,
  }) async {
    final params = <String, dynamic>{
      if (page != null) 'page': page,
      if (perPage != null) 'per_page': perPage,
      if (search != null) 'search': search,
      if (sort != null) 'sort': sort,
      if (sortDirection != null) 'sort_direction': sortDirection,
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
        // Fall through to local
      } on SalesProException {
        rethrow;
      }
    }

    // Fallback to local storage
    if (_isOfflineAvailable) {
      return _localList(params);
    }

    throw NetworkException(message: 'No internet connection and offline storage is not available');
  }

  /// Get a single contact by ID.
  Future<Contact> get(String id) async {
    // Try remote first
    if (_isOnline) {
      try {
        final response = await _httpClient.get('$_basePath/$id');
        final contact = Contact.fromJson(response.data as Map<String, dynamic>);

        // Cache locally
        if (_isOfflineAvailable && contact.id != null) {
          await _localDb!.upsertEntity(_table, contact.id!, response.data as Map<String, dynamic>);
        }

        return contact;
      } on NetworkException {
        // Fall through to local
      } on SalesProException {
        rethrow;
      }
    }

    // Fallback to local
    if (_isOfflineAvailable) {
      final data = await _localDb!.getEntity(_table, id);
      if (data != null) return Contact.fromJson(data);
      throw NotFoundException(message: 'Contact $id not found locally');
    }

    throw NetworkException(message: 'No internet connection');
  }

  /// Create a new contact.
  ///
  /// Saves locally as dirty first, then pushes to server.
  /// If offline, the create is queued for auto-sync.
  Future<Contact> create(Contact contact) async {
    // Assign a temporary local ID if none exists
    final localId = contact.id ?? 'local_${_uuid.v4()}';
    final contactWithId = contact.copyWith(id: localId);
    final json = contactWithId.toJson();

    // Save locally as dirty
    if (_isOfflineAvailable) {
      await _localDb!.upsertEntity(_table, localId, json, isDirty: true);
    }

    // Try remote
    if (_isOnline) {
      try {
        final response = await _httpClient.post(_basePath, body: json);
        final created = Contact.fromJson(response.data as Map<String, dynamic>);

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
        if (_syncQueue != null) {
          await _syncQueue!.enqueue(
            entityType: _entityType,
            entityId: localId,
            operation: 'create',
            path: _basePath,
            body: json,
          );
        }
        return contactWithId;
      } on SalesProException {
        rethrow;
      }
    }

    // Offline — queue it
    if (_syncQueue != null) {
      await _syncQueue!.enqueue(
        entityType: _entityType,
        entityId: localId,
        operation: 'create',
        path: _basePath,
        body: json,
      );
    }

    return contactWithId;
  }

  /// Update an existing contact.
  Future<Contact> update(String id, Contact contact) async {
    final json = contact.toJson();

    // Save locally as dirty
    if (_isOfflineAvailable) {
      await _localDb!.upsertEntity(_table, id, json, isDirty: true);
    }

    // Try remote
    if (_isOnline) {
      try {
        final response =
            await _httpClient.put('$_basePath/$id', body: json);
        final updated = Contact.fromJson(response.data as Map<String, dynamic>);

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
        // Queue for later
        if (_syncQueue != null) {
          await _syncQueue!.enqueue(
            entityType: _entityType,
            entityId: id,
            operation: 'update',
            path: '$_basePath/$id',
            body: json,
          );
        }
        return contact;
      } on SalesProException {
        rethrow;
      }
    }

    // Offline — queue it
    if (_syncQueue != null) {
      await _syncQueue!.enqueue(
        entityType: _entityType,
        entityId: id,
        operation: 'update',
        path: '$_basePath/$id',
        body: json,
      );
    }

    return contact;
  }

  /// Partially update a contact.
  Future<Contact> patch(String id, Map<String, dynamic> fields) async {
    // Merge with existing local data
    if (_isOfflineAvailable) {
      final existing = await _localDb!.getEntity(_table, id);
      if (existing != null) {
        final merged = {...existing, ...fields};
        await _localDb!.upsertEntity(_table, id, merged, isDirty: true);
      }
    }

    // Try remote
    if (_isOnline) {
      try {
        final response = await _httpClient.patch('$_basePath/$id', body: fields);
        final updated = Contact.fromJson(response.data as Map<String, dynamic>);

        if (_isOfflineAvailable) {
          await _localDb!.upsertEntity(
            _table,
            id,
            response.data as Map<String, dynamic>,
          );
        }

        return updated;
      } on NetworkException {
        if (_syncQueue != null) {
          await _syncQueue!.enqueue(
            entityType: _entityType,
            entityId: id,
            operation: 'patch',
            path: '$_basePath/$id',
            body: fields,
          );
        }
        final data = await _localDb?.getEntity(_table, id);
        return Contact.fromJson(data ?? fields);
      } on SalesProException {
        rethrow;
      }
    }

    // Offline — queue it
    if (_syncQueue != null) {
      await _syncQueue!.enqueue(
        entityType: _entityType,
        entityId: id,
        operation: 'patch',
        path: '$_basePath/$id',
        body: fields,
      );
    }

    final data = await _localDb?.getEntity(_table, id);
    return Contact.fromJson(data ?? fields);
  }

  /// Delete a contact.
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
    if (_syncQueue != null) {
      await _syncQueue!.enqueue(
        entityType: _entityType,
        entityId: id,
        operation: 'delete',
        path: '$_basePath/$id',
      );
    }
  }

  /// Search contacts by keyword.
  Future<ApiResponse> search(String query, {int? page, int? perPage}) async {
    return list(search: query, page: page, perPage: perPage);
  }

  /// Get contacts by type.
  Future<ApiResponse> byType(String type, {int? page, int? perPage}) async {
    return list(filters: {'type': type}, page: page, perPage: perPage);
  }

  // ── Private helpers ──────────────────────────────────────

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

    final entities = await _localDb!.getAllEntities(
      _table,
      limit: limit,
      offset: offset,
    );

    // Apply search filter locally
    var filtered = entities;
    if (params['search'] != null) {
      final query = params['search'].toString().toLowerCase();
      filtered = entities.where((e) {
        final name = '${e['first_name'] ?? ''} ${e['last_name'] ?? ''}'.toLowerCase();
        final email = (e['email'] ?? '').toString().toLowerCase();
        return name.contains(query) || email.contains(query);
      }).toList();
    }

    // Apply type filter locally
    if (params['type'] != null) {
      filtered = filtered
          .where((e) => e['type'] == params['type'] || e['contact_type'] == params['type'])
          .toList();
    }

    final totalCount = await _localDb!.countEntities(_table);

    return ApiResponse(
      success: true,
      statusCode: 200,
      data: {
        'data': filtered,
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