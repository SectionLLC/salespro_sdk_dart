import '../client/http_client.dart';
import '../models/quote.dart';
import '../models/api_response.dart';

/// Service for CRUD operations on Quotes / Estimates.
class QuoteService {
  static const String _basePath = '/quotes';

  final SalesProHttpClient _httpClient;

  QuoteService({required SalesProHttpClient httpClient})
      : _httpClient = httpClient;

  /// List quotes with optional filters and pagination.
  Future<ApiResponse> list({
    int? page,
    int? perPage,
    String? status,
    String? contactId,
    Map<String, dynamic>? filters,
  }) async {
    final params = <String, dynamic>{
      if (page != null) 'page': page,
      if (perPage != null) 'per_page': perPage,
      if (status != null) 'status': status,
      if (contactId != null) 'contact_id': contactId,
      ...?filters,
    };
    return _httpClient.get(_basePath, queryParams: params);
  }

  /// Get a single quote by ID.
  Future<Quote> get(String id) async {
    final response = await _httpClient.get('$_basePath/$id');
    return Quote.fromJson(response.data as Map<String, dynamic>);
  }

  /// Create a new quote.
  Future<Quote> create(Quote quote) async {
    final response = await _httpClient.post(_basePath, body: quote.toJson());
    return Quote.fromJson(response.data as Map<String, dynamic>);
  }

  /// Update a quote.
  Future<Quote> update(String id, Quote quote) async {
    final response =
        await _httpClient.put('$_basePath/$id', body: quote.toJson());
    return Quote.fromJson(response.data as Map<String, dynamic>);
  }

  /// Delete a quote.
  Future<void> delete(String id) async {
    await _httpClient.delete('$_basePath/$id');
  }

  /// Change quote status (e.g. 'sent', 'accepted', 'declined').
  Future<Quote> changeStatus(String id, String status) async {
    final response = await _httpClient.patch(
      '$_basePath/$id/status',
      body: {'status': status},
    );
    return Quote.fromJson(response.data as Map<String, dynamic>);
  }

  /// Send the quote via email.
  Future<void> send(String id, {String? email}) async {
    await _httpClient.post('$_basePath/$id/send', body: {
      if (email != null) 'email': email,
    });
  }

  /// Convert an accepted quote to a sales order.
  Future<Map<String, dynamic>> convertToOrder(String id) async {
    final response = await _httpClient.post('$_basePath/$id/convert');
    return response.data as Map<String, dynamic>;
  }
}