import '../client/http_client.dart';
import '../models/order.dart';
import '../models/api_response.dart';

/// Service for CRUD operations on Sales Orders.
class OrderService {
  static const String _basePath = '/orders';

  final SalesProHttpClient _httpClient;

  OrderService({required SalesProHttpClient httpClient})
      : _httpClient = httpClient;

  /// List orders with optional filters and pagination.
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
    return _httpClient.get(_basePath, queryParams: params);
  }

  /// Get a single order by ID.
  Future<Order> get(String id) async {
    final response = await _httpClient.get('$_basePath/$id');
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Create a new order.
  Future<Order> create(Order order) async {
    final response = await _httpClient.post(_basePath, body: order.toJson());
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Update an existing order.
  Future<Order> update(String id, Order order) async {
    final response =
        await _httpClient.put('$_basePath/$id', body: order.toJson());
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Delete an order.
  Future<void> delete(String id) async {
    await _httpClient.delete('$_basePath/$id');
  }

  /// Change order status (e.g. 'confirmed', 'shipped', 'delivered', 'cancelled').
  Future<Order> changeStatus(String id, String status) async {
    final response =
        await _httpClient.patch('$_basePath/$id/status', body: {'status': status});
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Convert a quote to an order.
  Future<Order> convertFromQuote(String quoteId) async {
    final response = await _httpClient.post(
      '$_basePath/from-quote',
      body: {'quote_id': quoteId},
    );
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Add a line item to an existing order.
  Future<Order> addLineItem(String orderId, OrderLineItem item) async {
    final response = await _httpClient.post(
      '$_basePath/$orderId/line-items',
      body: item.toJson(),
    );
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Remove a line item from an order.
  Future<Order> removeLineItem(String orderId, String lineItemId) async {
    final response = await _httpClient.delete(
      '$_basePath/$orderId/line-items/$lineItemId',
    );
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Calculate order totals (without persisting).
  Future<Map<String, dynamic>> calculateTotals(Order order) async {
    final response = await _httpClient.post(
      '$_basePath/calculate',
      body: order.toJson(),
    );
    return response.data as Map<String, dynamic>;
  }
}