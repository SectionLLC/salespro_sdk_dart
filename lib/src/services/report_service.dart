import '../client/http_client.dart';
import '../storage/local_database.dart';
import '../storage/connectivity_monitor.dart';
import '../models/report.dart';
import '../models/api_response.dart';
import '../exceptions/sdk_exceptions.dart';

class ReportService {
  static const String _basePath = '/reports';
  static const String _table = LocalDatabase.reportsTable;

  final SalesProHttpClient _httpClient;
  final LocalDatabase? _localDb;
  final ConnectivityMonitor? _connectivityMonitor;

  ReportService({
    required SalesProHttpClient httpClient,
    LocalDatabase? localDb, ConnectivityMonitor? connectivityMonitor,
  })  : _httpClient = httpClient, _localDb = localDb,
        _connectivityMonitor = connectivityMonitor;

  bool get _isOfflineAvailable => _localDb != null;
  bool get _isOnline => _connectivityMonitor?.isOnline ?? true;

  Future<ApiResponse> list() async {
    if (_isOnline) {
      try { return _httpClient.get(_basePath); }
      on NetworkException {} on SalesProException { rethrow; }
    }
    if (_isOfflineAvailable) {
      final entities = await _localDb!.getAllEntities(_table);
      return ApiResponse(success: true, statusCode: 200, data: {'data': entities});
    }
    throw NetworkException(message: 'No internet connection');
  }

  Future<Report> get(String reportId) async {
    if (_isOnline) {
      try {
        final response = await _httpClient.get('$_basePath/$reportId');
        final report = Report.fromJson(response.data as Map<String, dynamic>);
        if (_isOfflineAvailable && report.id != null) {
          await _localDb!.upsertEntity(_table, report.id!, response.data as Map<String, dynamic>);
        }
        return report;
      } on NetworkException {} on SalesProException { rethrow; }
    }

    if (_isOfflineAvailable) {
      final data = await _localDb!.getEntity(_table, reportId);
      if (data != null) return Report.fromJson(data);
      throw NotFoundException(message: 'Report $reportId not found locally');
    }
    throw NetworkException(message: 'No internet connection');
  }

  Future<SalesSummary> salesSummary({DateTime? dateFrom, DateTime? dateTo, String? groupBy}) async {
    if (!_isOnline) throw NetworkException(message: 'Reports require internet connection');
    final response = await _httpClient.get('$_basePath/sales-summary', queryParams: {
      if (dateFrom != null) 'date_from': dateFrom.toIso8601String(),
      if (dateTo != null) 'date_to': dateTo.toIso8601String(),
      if (groupBy != null) 'group_by': groupBy,
    });
    return SalesSummary.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Report> revenue({required DateTime dateFrom, required DateTime dateTo, String? groupBy}) async {
    if (!_isOnline) throw NetworkException(message: 'Reports require internet connection');
    final response = await _httpClient.get('$_basePath/revenue', queryParams: {
      'date_from': dateFrom.toIso8601String(), 'date_to': dateTo.toIso8601String(),
      if (groupBy != null) 'group_by': groupBy,
    });
    return Report.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Report> inventoryValuation({String? warehouse}) async {
    if (!_isOnline) throw NetworkException(message: 'Reports require internet connection');
    final response = await _httpClient.get('$_basePath/inventory-valuation', queryParams: {
      if (warehouse != null) 'warehouse': warehouse,
    });
    return Report.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Report> topCustomers({DateTime? dateFrom, DateTime? dateTo, int? limit}) async {
    if (!_isOnline) throw NetworkException(message: 'Reports require internet connection');
    final response = await _httpClient.get('$_basePath/top-customers', queryParams: {
      if (dateFrom != null) 'date_from': dateFrom.toIso8601String(),
      if (dateTo != null) 'date_to': dateTo.toIso8601String(),
      if (limit != null) 'limit': limit,
    });
    return Report.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Report> custom({required String template, Map<String, dynamic>? parameters}) async {
    if (!_isOnline) throw NetworkException(message: 'Reports require internet connection');
    final response = await _httpClient.post('$_basePath/custom', body: {
      'template': template, if (parameters != null) 'parameters': parameters,
    });
    return Report.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ApiResponse> export(String reportId, {String format = 'pdf'}) async {
    if (!_isOnline) throw NetworkException(message: 'Export requires internet connection');
    return _httpClient.get('$_basePath/$reportId/export', queryParams: {'format': format});
  }
}