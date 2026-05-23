import '../client/http_client.dart';
import '../models/report.dart';
import '../models/api_response.dart';

/// Service for report operations.
class ReportService {
  static const String _basePath = '/reports';

  final SalesProHttpClient _httpClient;

  ReportService({required SalesProHttpClient httpClient})
      : _httpClient = httpClient;

  /// List available report types.
  Future<ApiResponse> list() async {
    return _httpClient.get(_basePath);
  }

  /// Get a specific report.
  Future<Report> get(String reportId) async {
    final response = await _httpClient.get('$_basePath/$reportId');
    return Report.fromJson(response.data as Map<String, dynamic>);
  }

  /// Generate a sales summary report.
  Future<SalesSummary> salesSummary({
    DateTime? dateFrom,
    DateTime? dateTo,
    String? groupBy, // 'day', 'week', 'month', 'quarter', 'year'
  }) async {
    final response = await _httpClient.get(
      '$_basePath/sales-summary',
      queryParams: {
        if (dateFrom != null) 'date_from': dateFrom.toIso8601String(),
        if (dateTo != null) 'date_to': dateTo.toIso8601String(),
        if (groupBy != null) 'group_by': groupBy,
      },
    );
    return SalesSummary.fromJson(response.data as Map<String, dynamic>);
  }

  /// Generate a revenue report.
  Future<Report> revenue({
    required DateTime dateFrom,
    required DateTime dateTo,
    String? groupBy,
  }) async {
    final response = await _httpClient.get(
      '$_basePath/revenue',
      queryParams: {
        'date_from': dateFrom.toIso8601String(),
        'date_to': dateTo.toIso8601String(),
        if (groupBy != null) 'group_by': groupBy,
      },
    );
    return Report.fromJson(response.data as Map<String, dynamic>);
  }

  /// Generate an inventory valuation report.
  Future<Report> inventoryValuation({String? warehouse}) async {
    final response = await _httpClient.get(
      '$_basePath/inventory-valuation',
      queryParams: {
        if (warehouse != null) 'warehouse': warehouse,
      },
    );
    return Report.fromJson(response.data as Map<String, dynamic>);
  }

  /// Generate a top customers report.
  Future<Report> topCustomers({
    DateTime? dateFrom,
    DateTime? dateTo,
    int? limit,
  }) async {
    final response = await _httpClient.get(
      '$_basePath/top-customers',
      queryParams: {
        if (dateFrom != null) 'date_from': dateFrom.toIso8601String(),
        if (dateTo != null) 'date_to': dateTo.toIso8601String(),
        if (limit != null) 'limit': limit,
      },
    );
    return Report.fromJson(response.data as Map<String, dynamic>);
  }

  /// Generate a custom report from a template.
  Future<Report> custom({
    required String template,
    Map<String, dynamic>? parameters,
  }) async {
    final response = await _httpClient.post(
      '$_basePath/custom',
      body: {
        'template': template,
        if (parameters != null) 'parameters': parameters,
      },
    );
    return Report.fromJson(response.data as Map<String, dynamic>);
  }

  /// Export a report in the given format ('pdf', 'csv', 'xlsx').
  Future<ApiResponse> export(String reportId, {String format = 'pdf'}) async {
    return _httpClient.get(
      '$_basePath/$reportId/export',
      queryParams: {'format': format},
    );
  }
}