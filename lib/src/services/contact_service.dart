import '../client/http_client.dart';
import '../models/contact.dart';
import '../models/api_response.dart';

/// Service for CRUD operations on Contacts / Customers.
class ContactService {
  static const String _basePath = '/contacts';

  final SalesProHttpClient _httpClient;

  ContactService({required SalesProHttpClient httpClient})
      : _httpClient = httpClient;

  /// List contacts with optional filters and pagination.
  ///
  /// ```dart
  /// final result = await sdk.contacts.list(
  ///   page: 2,
  ///   perPage: 50,
  ///   filters: {'type': 'customer', 'status': 'active'},
  /// );
  /// final contacts = result.items<Contact>(Contact.fromJson);
  /// ```
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

    return _httpClient.get(_basePath, queryParams: params);
  }

  /// Get a single contact by ID.
  Future<Contact> get(String id) async {
    final response = await _httpClient.get('$_basePath/$id');
    return Contact.fromJson(response.data as Map<String, dynamic>);
  }

  /// Create a new contact.
  Future<Contact> create(Contact contact) async {
    final response = await _httpClient.post(_basePath, body: contact.toJson());
    return Contact.fromJson(response.data as Map<String, dynamic>);
  }

  /// Update an existing contact.
  Future<Contact> update(String id, Contact contact) async {
    final response =
        await _httpClient.put('$_basePath/$id', body: contact.toJson());
    return Contact.fromJson(response.data as Map<String, dynamic>);
  }

  /// Partially update a contact.
  Future<Contact> patch(String id, Map<String, dynamic> fields) async {
    final response = await _httpClient.patch('$_basePath/$id', body: fields);
    return Contact.fromJson(response.data as Map<String, dynamic>);
  }

  /// Delete a contact.
  Future<void> delete(String id) async {
    await _httpClient.delete('$_basePath/$id');
  }

  /// Search contacts by keyword.
  Future<ApiResponse> search(String query, {int? page, int? perPage}) async {
    return list(search: query, page: page, perPage: perPage);
  }

  /// Get all contacts of a specific type (e.g. 'customer', 'vendor', 'lead').
  Future<ApiResponse> byType(String type, {int? page, int? perPage}) async {
    return list(filters: {'type': type}, page: page, perPage: perPage);
  }
}