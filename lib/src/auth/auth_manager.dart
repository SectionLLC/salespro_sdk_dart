import '../client/http_client.dart';
import '../config/sdk_config.dart';
import '../exceptions/sdk_exceptions.dart';

/// Manages authentication state and operations.
class AuthManager {
  final SalesProHttpClient _httpClient;
  final SalesProConfig _config;

  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;

  AuthManager({
    required SalesProHttpClient httpClient,
    required SalesProConfig config,
  })  : _httpClient = httpClient,
        _config = config;

  /// Whether the SDK currently holds a valid (non-expired) token.
  bool get isAuthenticated {
    if (_accessToken == null) return false;
    if (_expiresAt != null && _expiresAt!.isBefore(DateTime.now())) return false;
    return true;
  }

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;

  /// ── Login with OAuth2 Resource Owner Password Grant ──────
  ///
  /// Requires `clientId` and `clientSecret` to be set in [SalesProConfig].
  /// Sends `grant_type=password`, `username`, `password`, `scope`, etc.
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    if (_config.clientId == null || _config.clientSecret == null) {
      throw AuthenticationException(
        message: 'OAuth2 requires clientId and clientSecret in SalesProConfig',
      );
    }

    final body = <String, String>{
      'grant_type': 'password',
      'client_id': _config.clientId!,
      'client_secret': _config.clientSecret!,
      'username': username,
      'password': password,
    };

    // Include scope if provided in config
    if (_config.scope != null && _config.scope!.isNotEmpty) {
      body['scope'] = _config.scope!;
    }

    final response = await _httpClient.postForm(
      '/oauth/token', // Standard OAuth2 token endpoint
      body: body,
    );

    final data = response.data as Map<String, dynamic>;
    _applyTokens(data);
    return data;
  }

  /// ── Login with API key only ──────────────────────────────
  Future<void> loginWithApiKey(String apiKey) async {
    _config.apiKey = apiKey;
    try {
      await _httpClient.get('/auth/verify');
    } catch (e) {
      _config.apiKey = null;
      rethrow;
    }
  }

  /// ── Refresh the access token ─────────────────────────────
  Future<void> refresh() async {
    if (_refreshToken == null) {
      throw AuthenticationException(message: 'No refresh token available');
    }

    if (_config.clientId == null || _config.clientSecret == null) {
      throw AuthenticationException(
        message: 'OAuth2 requires clientId and clientSecret to refresh tokens',
      );
    }

    final response = await _httpClient.postForm(
      '/oauth/token',
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': _refreshToken!,
        'client_id': _config.clientId!,
        'client_secret': _config.clientSecret!,
      },
    );

    final data = response.data as Map<String, dynamic>;
    _applyTokens(data);
  }

  /// ── Logout (invalidate server-side) ──────────────────────
  Future<void> logout() async {
    try {
      await _httpClient.post('/auth/logout');
    } catch (_) {
      // Swallow — we're clearing local state regardless
    } finally {
      _clearTokens();
    }
  }

  /// ── Get current authenticated user profile ───────────────
  Future<Map<String, dynamic>> me() async {
    final response = await _httpClient.get('/auth/me');
    return response.data as Map<String, dynamic>;
  }

  // ── Private helpers ──────────────────────────────────────

  void _applyTokens(Map<String, dynamic> data) {
    _accessToken = data['access_token'] ?? data['token'] as String?;
    _refreshToken = data['refresh_token'] as String?;

    // Parse expiry
    final expiresIn = data['expires_in'];
    if (expiresIn is int) {
      _expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
    } else if (data['expires_at'] != null) {
      _expiresAt = DateTime.tryParse(data['expires_at'].toString());
    }

    // Push token to config so the HTTP client uses it automatically
    _config.bearerToken = _accessToken;
  }

  void _clearTokens() {
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    _config.bearerToken = null;
  }
}