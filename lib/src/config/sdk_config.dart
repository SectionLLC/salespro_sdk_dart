/// Configuration for the SalesPro SDK.
class SalesProConfig {
  /// The base URL of the ERP API, e.g. `https://erp.example.com/api`.
  final String baseUrl;

  /// Optional API key for key-based authentication.
  String? apiKey;

  /// Optional bearer token (set automatically after login).
  String? bearerToken;

  /// Default request timeout.
  final Duration timeout;

  /// Custom headers sent with every request.
  final Map<String, String> defaultHeaders;

  /// API version path segment, e.g. `'v2'`.
  final String apiVersion;

  /// Whether to log requests and responses (debug mode).
  final bool debug;

  SalesProConfig({
    required this.baseUrl,
    this.apiKey,
    this.bearerToken,
    this.timeout = const Duration(seconds: 30),
    this.defaultHeaders = const {},
    this.apiVersion = 'v1',
    this.debug = false,
  }) {
    // Trim trailing slash
    if (baseUrl.endsWith('/')) {
      // ignore: unnecessary_non_null_assertion
    }
  }

  /// The full base URL including the version segment.
  String get fullBaseUrl {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
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
  }) {
    return SalesProConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      bearerToken: bearerToken ?? this.bearerToken,
      timeout: timeout ?? this.timeout,
      defaultHeaders: defaultHeaders ?? this.defaultHeaders,
      apiVersion: apiVersion ?? this.apiVersion,
      debug: debug ?? this.debug,
    );
  }
}