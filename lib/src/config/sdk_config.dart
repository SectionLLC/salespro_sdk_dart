/// Configuration for the SalesPro SDK.
class SalesProConfig {
  final String baseUrl;
  final String? apiKey;
  String? bearerToken;
  final Duration timeout;

  /// Custom headers sent with every request.
  final Map<String, String> defaultHeaders;

  /// API version path segment.
  final String apiVersion;

  /// Whether to log requests and responses.
  final bool debug;

  /// Whether to enable offline storage and auto-sync.
  final bool offlineEnabled;

  /// How often to attempt a periodic sync when online.
  final Duration? syncInterval;

  /// Timestamp of the last successful sync (used for incremental pulls).
  DateTime? lastSyncTimestamp;

  /// How many items to pull per entity type during sync.
  final int syncBatchSize;

  SalesProConfig({
    required this.baseUrl,
    this.apiKey,
    this.bearerToken,
    this.timeout = const Duration(seconds: 30),
    this.defaultHeaders = const {},
    this.apiVersion = 'v1',
    this.debug = false,
    this.offlineEnabled = true,
    this.syncInterval = const Duration(minutes: 5),
    this.lastSyncTimestamp,
    this.syncBatchSize = 500,
  });

  /// The full base URL including the version segment.
  String get fullBaseUrl {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$base/$apiVersion';
  }

  SalesProConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? bearerToken,
    Duration? timeout,
    Map<String, String>? defaultHeaders,
    String? apiVersion,
    bool? debug,
    bool? offlineEnabled,
    Duration? syncInterval,
    DateTime? lastSyncTimestamp,
    int? syncBatchSize,
  }) {
    return SalesProConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      bearerToken: bearerToken ?? this.bearerToken,
      timeout: timeout ?? this.timeout,
      defaultHeaders: defaultHeaders ?? this.defaultHeaders,
      apiVersion: apiVersion ?? this.apiVersion,
      debug: debug ?? this.debug,
      offlineEnabled: offlineEnabled ?? this.offlineEnabled,
      syncInterval: syncInterval ?? this.syncInterval,
      lastSyncTimestamp: lastSyncTimestamp ?? this.lastSyncTimestamp,
      syncBatchSize: syncBatchSize ?? this.syncBatchSize,
    );
  }
}