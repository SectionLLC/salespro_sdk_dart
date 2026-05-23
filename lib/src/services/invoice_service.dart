import '../client/http_client.dart';
import '../models/invoice.dart';
import '../models/api_response.dart';

/// Service for CRUD operations on Invoices.
class InvoiceService {
  static const String _basePath = '/invoices';

  final SalesProHttpClient _httpClient;

  InvoiceService({required SalesProHttpClient httpClient})
      : _httpClient = httpClient;

  /// List invoices with optional filters and pagination.
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

  /// Get a single invoice by ID.
  Future<Invoice> get(String id) async {
    final response = await _httpClient.get('$_basePath/$id');
    return Invoice.fromJson(response.data as Map<String, dynamic>);
  }

  /// Create a new invoice (standalone).
  Future<Invoice> create(Invoice invoice) async {
    final response = await _httpClient.post(_basePath, body: invoice.toJson());
    return Invoice.fromJson(response.data as Map<String, dynamic>);
  }

  /// Generate an invoice from an existing order.
  Future<Invoice> createFromOrder(String orderId) async {
    final response = await _httpClient.post(
      '$_basePath/from-order',
      body: {'order_id': orderId},
    );
    return Invoice.fromJson(response.data as Map<String, dynamic>);
  }

  /// Update an invoice.
  Future<Invoice> update(String id, Invoice invoice) async {
    final response =
        await _httpClient.put('$_basePath/$id', body: invoice.toJson());
    return Invoice.fromJson(response.data as Map<String, dynamic>);
  }

  /// Delete an invoice.
  Future<void> delete(String id) async {
    await _httpClient.delete('$_basePath/$id');
  }

  /// Change invoice status (e.g. 'sent', 'paid', 'cancelled').
  Future<Invoice> changeStatus(String id, String status) async {
    final response = await _httpClient.patch(
      '$_basePath/$id/status',
      body: {'status': status},
    );
    return Invoice.fromJson(response.data as Map<String, dynamic>);
  }

  /// Record a payment against an invoice.
  Future<Invoice> recordPayment(String id, {
    required double amount,
    String? paymentMethod,
    String? reference,
    DateTime? paymentDate,
  }) async {
    final response = await _httpClient.post(
      '$_basePath/$id/payments',
      body: {
        'amount': amount,
        if (paymentMethod != null) 'payment_method': paymentMethod,
        if (reference != null) 'reference': reference,
        if (paymentDate != null) 'payment_date': paymentDate.toIso8601String(),
      },
    );
    return Invoice.fromJson(response.data as Map<String, dynamic>);
  }

  /// Send the invoice via email.
  Future<void> send(String id, {String? email}) async {
    await _httpClient.post('$_basePath/$id/send', body: {
      if (email != null) 'email': email,
    });
  }

  /// Download the invoice as PDF (returns raw bytes).
  Future<List<int>> downloadPdf(String id) async {
    // This is a special case — we need raw bytes, not JSON
    // The HTTP client's generic _request would need a raw variant.
    // For simplicity, we make a direct request here.
    Uri.parse('${_httpClient.config.fullBaseUrl}/$_basePath/$id/pdf');
    final headers = <String, String>{};
    if (_httpClient.config.bearerToken != null) {
      headers['Authorization'] = 'Bearer ${_httpClient.config.bearerToken}';
    }
    if (_httpClient.config.apiKey != null) {
      headers['X-API-Key'] = _httpClient.config.apiKey!;
    }
    // Using a standard http.Client for the raw download
    // Note: In production you'd expose a raw request method on the client.
    // Here we approximate:
    final response = await _httpClient.get('$_basePath/$id/pdf');
    // If the API returns base64-encoded PDF:
    if (response.data is String) {
      return _decodeBase64(response.data as String);
    }
    return [];
  }

  List<int> _decodeBase64(String encoded) {
    // ignore: avoid_web_libraries_in_flutter
    return Uri.parse('data:application/pdf;base64,$encoded')
        .data!
        .contentAsBytes();
  }
}