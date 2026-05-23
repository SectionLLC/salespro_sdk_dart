import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/sdk_config.dart';
import '../exceptions/sdk_exceptions.dart';
import '../models/api_response.dart';

/// HTTP method enum.
enum HttpMethod { get, post, put, patch, delete }

/// Internal HTTP client that handles authentication headers,
/// serialization, error mapping, and debug logging.
class SalesProHttpClient {
  final SalesProConfig config;
  final http.Client _inner;

  SalesProHttpClient({required this.config, http.Client? innerClient})
      : _inner = innerClient ?? http.Client();

  /// Build the full URL for a given [path].
  Uri _buildUri(String path, [Map<String, dynamic>? queryParams]) {
    final base = config.fullBaseUrl;
    final fullPath = path.startsWith('/') ? '$base$path' : '$base/$path';

    final params = <String, String>{};
    queryParams?.forEach((key, value) {
      if (value != null) params[key] = value.toString();
    });

    return Uri.parse(fullPath).replace(queryParameters: params.isEmpty ? null : params);
  }

  /// Merge default headers + auth headers.
  Map<String, String> _buildHeaders({Map<String, String>? extra}) {
    final headers = <String, String>{
      'Accept': 'application/json',
      ...config.defaultHeaders,
    };

    // API key header
    if (config.apiKey != null && config.apiKey!.isNotEmpty) {
      headers['X-API-Key'] = config.apiKey!;
    }

    // Bearer token
    if (config.bearerToken != null && config.bearerToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.bearerToken}';
    }

    if (extra != null) {
      headers.addAll(extra);
    }

    return headers;
  }

  // ── Generic request method ──────────────────────────────

  Future<ApiResponse> _request(
    HttpMethod method,
    String path, {
    Map<String, dynamic>? queryParams,
    dynamic body,
    Map<String, String>? extraHeaders,
  }) async {
    final uri = _buildUri(path, queryParams);
    
    // Determine Content-Type dynamically (JSON by default, unless overridden by extraHeaders)
    final isFormRequest = extraHeaders?['Content-Type'] == 'application/x-www-form-urlencoded';
    
    final headers = _buildHeaders(extra: extraHeaders);
    if (!isFormRequest) {
      headers['Content-Type'] = 'application/json';
    }

    _log('--> $method ${uri.toString()}');
    if (body != null) _log('    Body: $body');

    http.Response response;

    try {
      final encodedBody = body != null 
          ? (isFormRequest ? body as String : jsonEncode(body)) 
          : null;

      switch (method) {
        case HttpMethod.get:
          response = await _inner.get(uri, headers: headers).timeout(config.timeout);
          break;
        case HttpMethod.post:
          response = await _inner.post(uri, headers: headers, body: encodedBody).timeout(config.timeout);
          break;
        case HttpMethod.put:
          response = await _inner.put(uri, headers: headers, body: encodedBody).timeout(config.timeout);
          break;
        case HttpMethod.patch:
          response = await _inner.patch(uri, headers: headers, body: encodedBody).timeout(config.timeout);
          break;
        case HttpMethod.delete:
          response = await _inner.delete(uri, headers: headers, body: encodedBody).timeout(config.timeout);
          break;
      }
    } catch (e) {
      _log('<-- NETWORK ERROR: $e');
      throw NetworkException(message: 'Failed to connect to the server', originalError: e);
    }

    _log('<-- ${response.statusCode} ${uri.path}');
    _log('    Body: ${response.body}');

    return _handleResponse(response);
  }

  ApiResponse _handleResponse(http.Response response) {
    final statusCode = response.statusCode;
    final body = response.body;

    dynamic data;
    try {
      data = body.isNotEmpty ? jsonDecode(body) : null;
    } catch (_) {
      data = body;
    }

    // Success range
    if (statusCode >= 200 && statusCode < 300) {
      return ApiResponse(
        success: true,
        statusCode: statusCode,
        data: data,
        message: data is Map ? data['message'] as String? : null,
      );
    }

    // Error range
    final message = _extractErrorMessage(data) ?? 'Unknown error';

    switch (statusCode) {
      case 400:
        throw ValidationException(
          message: message,
          errors: data is Map ? Map<String, dynamic>.from(data['errors'] ?? {}) : null,
          responseBody: body,
        );
      case 401:
      case 403:
        throw AuthenticationException(message: message, statusCode: statusCode, responseBody: body);
      case 404:
        throw NotFoundException(message: message, responseBody: body);
      case 429:
        final retry = response.headers['retry-after'];
        throw RateLimitException(
          message: message,
          retryAfterSeconds: retry != null ? int.tryParse(retry) : null,
          responseBody: body,
        );
      default:
        if (statusCode >= 500) {
          throw ServerException(message: message, statusCode: statusCode, responseBody: body);
        }
        throw SalesProException(message: message, statusCode: statusCode, responseBody: body);
    }
  }

  String? _extractErrorMessage(dynamic data) {
    if (data is Map) {
      return data['message'] as String? ?? data['error'] as String? ?? data['error_description'] as String?;
    }
    if (data is String) return data;
    return null;
  }

  void _log(String message) {
    if (config.debug) {
      // ignore: avoid_print
      print('[SalesProSDK] $message');
    }
  }

  // ── Convenience methods ──────────────────────────────────

  Future<ApiResponse> get(String path, {Map<String, dynamic>? queryParams}) =>
      _request(HttpMethod.get, path, queryParams: queryParams);

  Future<ApiResponse> post(String path, {dynamic body}) =>
      _request(HttpMethod.post, path, body: body);

  Future<ApiResponse> put(String path, {dynamic body}) =>
      _request(HttpMethod.put, path, body: body);

  Future<ApiResponse> patch(String path, {dynamic body}) =>
      _request(HttpMethod.patch, path, body: body);

  Future<ApiResponse> delete(String path, {dynamic body}) =>
      _request(HttpMethod.delete, path, body: body);

  /// Post URL-encoded form data (required for OAuth2 token endpoints).
  Future<ApiResponse> postForm(String path, {required Map<String, String> body}) async {
    // Encode map to x-www-form-urlencoded string
    final encodedBody = body.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');

    return _request(
      HttpMethod.post,
      path,
      body: encodedBody,
      extraHeaders: {'Content-Type': 'application/x-www-form-urlencoded'},
    );
  }

  /// Close the underlying HTTP client.
  void dispose() {
    _inner.close();
  }
}