import '../client/http_client.dart';
import '../models/product.dart';
import '../models/api_response.dart';

/// Service for CRUD operations on Products / Items.
class ProductService {
  static const String _basePath = '/products';

  final SalesProHttpClient _httpClient;

  ProductService({required SalesProHttpClient httpClient})
      : _httpClient = httpClient;

  /// List products with optional filters and pagination.
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

    return _httpClient.get(_basePath, queryParams: params);
  }

  /// Get a single product by ID.
  Future<Product> get(String id) async {
    final response = await _httpClient.get('$_basePath/$id');
    return Product.fromJson(response.data as Map<String, dynamic>);
  }

  /// Get a product by SKU.
  Future<Product> getBySku(String sku) async {
    final response = await _httpClient.get('$_basePath/sku/$sku');
    return Product.fromJson(response.data as Map<String, dynamic>);
  }

  /// Create a new product.
  Future<Product> create(Product product) async {
    final response = await _httpClient.post(_basePath, body: product.toJson());
    return Product.fromJson(response.data as Map<String, dynamic>);
  }

  /// Update an existing product.
  Future<Product> update(String id, Product product) async {
    final response =
        await _httpClient.put('$_basePath/$id', body: product.toJson());
    return Product.fromJson(response.data as Map<String, dynamic>);
  }

  /// Partially update a product.
  Future<Product> patch(String id, Map<String, dynamic> fields) async {
    final response = await _httpClient.patch('$_basePath/$id', body: fields);
    return Product.fromJson(response.data as Map<String, dynamic>);
  }

  /// Delete a product.
  Future<void> delete(String id) async {
    await _httpClient.delete('$_basePath/$id');
  }

  /// Bulk update prices.
  Future<ApiResponse> bulkUpdatePrices(Map<String, double> priceMap) async {
    return _httpClient.post('$_basePath/bulk/prices', body: {
      'prices': priceMap,
    });
  }

  /// List product categories.
  Future<ApiResponse> categories() async {
    return _httpClient.get('/product-categories');
  }
}