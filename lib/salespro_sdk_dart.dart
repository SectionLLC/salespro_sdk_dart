/// SalesPro SDK for Flutter
///
/// A comprehensive SDK for connecting and communicating with
/// SalesPro ERP systems from Flutter applications.
library salespro_sdk;

// Core
export 'src/config/sdk_config.dart';
export 'src/client/http_client.dart';
export 'src/auth/auth_manager.dart';

// Models
export 'src/models/contact.dart';
export 'src/models/product.dart';
export 'src/models/order.dart';
export 'src/models/invoice.dart';
export 'src/models/quote.dart';
export 'src/models/inventory_item.dart';
export 'src/models/report.dart';
export 'src/models/api_response.dart';

// Services
export 'src/services/contact_service.dart';
export 'src/services/product_service.dart';
export 'src/services/order_service.dart';
export 'src/services/invoice_service.dart';
export 'src/services/quote_service.dart';
export 'src/services/inventory_service.dart';
export 'src/services/report_service.dart';

import 'src/config/sdk_config.dart';
import 'src/client/http_client.dart';
import 'src/auth/auth_manager.dart';
import 'src/services/contact_service.dart';
import 'src/services/product_service.dart';
import 'src/services/order_service.dart';
import 'src/services/invoice_service.dart';
import 'src/services/quote_service.dart';
import 'src/services/inventory_service.dart';
import 'src/services/report_service.dart';

/// The main SDK class — your single entry point for all ERP interactions.
///
/// ```dart
/// final sdk = SalesProSDK(
///   config: SalesProConfig(
///     baseUrl: 'https://erp.example.com/api',
///     apiKey: 'your-api-key',
///   ),
/// );
///
/// // Authenticate
/// await sdk.auth.login(username: 'admin', password: 'secret');
///
/// // Fetch contacts
/// final contacts = await sdk.contacts.list();
/// ```
class SalesProSDK {
  late final SalesProConfig _config;
  late final SalesProHttpClient _httpClient;
  late final AuthManager _authManager;

  // Services (lazy-initialized via getters)
  ContactService? _contactService;
  ProductService? _productService;
  OrderService? _orderService;
  InvoiceService? _invoiceService;
  QuoteService? _quoteService;
  InventoryService? _inventoryService;
  ReportService? _reportService;

  /// Create a new SDK instance with the given [config].
  SalesProSDK({required SalesProConfig config}) : _config = config {
    _httpClient = SalesProHttpClient(config: _config);
    _authManager = AuthManager(httpClient: _httpClient, config: _config);
  }

  /// Create an SDK instance with just a base URL and API key.
  factory SalesProSDK.withApiKey({
    required String baseUrl,
    required String apiKey,
  }) {
    return SalesProSDK(
      config: SalesProConfig(baseUrl: baseUrl, apiKey: apiKey),
    );
  }

  // ── Getters ────────────────────────────────────────────────

  /// Authentication manager for login / logout / token refresh.
  AuthManager get auth => _authManager;

  /// Contact / Customer CRUD operations.
  ContactService get contacts =>
      _contactService ??= ContactService(httpClient: _httpClient);

  /// Product / Item CRUD operations.
  ProductService get products =>
      _productService ??= ProductService(httpClient: _httpClient);

  /// Sales Order CRUD operations.
  OrderService get orders =>
      _orderService ??= OrderService(httpClient: _httpClient);

  /// Invoice CRUD operations.
  InvoiceService get invoices =>
      _invoiceService ??= InvoiceService(httpClient: _httpClient);

  /// Quote CRUD operations.
  QuoteService get quotes =>
      _quoteService ??= QuoteService(httpClient: _httpClient);

  /// Inventory operations.
  InventoryService get inventory =>
      _inventoryService ??= InventoryService(httpClient: _httpClient);

  /// Report operations.
  ReportService get reports =>
      _reportService ??= ReportService(httpClient: _httpClient);

  // ── Convenience ────────────────────────────────────────────

  /// Whether the SDK currently holds a valid authentication token.
  bool get isAuthenticated => _authManager.isAuthenticated;

  /// The current access token (may be null if not authenticated).
  String? get accessToken => _authManager.accessToken;

  /// Override the HTTP client (useful for testing).
  void setHttpClient(SalesProHttpClient client) {
    // ignore: unnecessary_non_null_assertion — intentional override
  }
}