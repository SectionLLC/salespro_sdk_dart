import '../client/http_client.dart';
import '../models/inventory_item.dart';
import '../models/api_response.dart';

/// Service for inventory operations.
class InventoryService {
  static const String _basePath = '/inventory';

  final SalesProHttpClient _httpClient;

  InventoryService({required SalesProHttpClient httpClient})
      : _httpClient = httpClient;

  /// List inventory items with optional filters.
  Future<ApiResponse> list({
    int? page,
    int? perPage,
    String? warehouse,
    bool? lowStock,
    String? sku,
    Map<String, dynamic>? filters,
  }) async {
    final params = <String, dynamic>{
      if (page != null) 'page': page,
      if (perPage != null) 'per_page': perPage,
      if (warehouse != null) 'warehouse': warehouse,
      if (lowStock != null) 'low_stock': lowStock,
      if (sku != null) 'sku': sku,
      ...?filters,
    };
    return _httpClient.get(_basePath, queryParams: params);
  }

  /// Get inventory for a specific product.
  Future<InventoryItem> get(String productId) async {
    final response = await _httpClient.get('$_basePath/$productId');
    return InventoryItem.fromJson(response.data as Map<String, dynamic>);
  }

  /// Adjust stock quantity for a product.
  Future<InventoryItem> adjust({
    required String productId,
    required int quantity,
    required String reason, // 'sale', 'return', 'adjustment', 'transfer'
    String? warehouse,
    String? reference,
  }) async {
    final response = await _httpClient.post('$_basePath/adjust', body: {
      'product_id': productId,
      'quantity': quantity,
      'reason': reason,
      if (warehouse != null) 'warehouse': warehouse,
      if (reference != null) 'reference': reference,
    });
    return InventoryItem.fromJson(response.data as Map<String, dynamic>);
  }

  /// Transfer stock between warehouses.
  Future<ApiResponse> transfer({
    required String productId,
    required int quantity,
    required String fromWarehouse,
    required String toWarehouse,
  }) async {
    return _httpClient.post('$_basePath/transfer', body: {
      'product_id': productId,
      'quantity': quantity,
      'from_warehouse': fromWarehouse,
      'to_warehouse': toWarehouse,
    });
  }

  /// Get items that are below reorder point.
  Future<ApiResponse> lowStock({int? page, int? perPage}) async {
    return list(lowStock: true, page: page, perPage: perPage);
  }

  /// List all warehouses.
  Future<ApiResponse> warehouses() async {
    return _httpClient.get('/warehouses');
  }

  /// Get stock history for a product.
  Future<ApiResponse> history(String productId, {
    int? page,
    int? perPage,
  }) async {
    return _httpClient.get(
      '$_basePath/$productId/history',
      queryParams: {
        if (page != null) 'page': page,
        if (perPage != null) 'per_page': perPage,
      },
    );
  }
}