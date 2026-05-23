/// Base exception for all SDK errors.
class SalesProException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;
  final dynamic originalError;

  SalesProException({
    required this.message,
    this.statusCode,
    this.responseBody,
    this.originalError,
  });

  @override
  String toString() => 'SalesProException($statusCode): $message';
}

/// Thrown when authentication fails (401).
class AuthenticationException extends SalesProException {
  AuthenticationException({
    String? message,
    int? statusCode,
    String? responseBody,
  }) : super(
          message: message ?? 'Authentication failed',
          statusCode: statusCode ?? 401,
          responseBody: responseBody,
        );
}

/// Thrown when the requested resource is not found (404).
class NotFoundException extends SalesProException {
  NotFoundException({
    String? message,
    String? responseBody,
  }) : super(
          message: message ?? 'Resource not found',
          statusCode: 404,
          responseBody: responseBody,
        );
}

/// Thrown for validation / bad-request errors (400).
class ValidationException extends SalesProException {
  final Map<String, dynamic>? errors;

  ValidationException({
    String? message,
    this.errors,
    String? responseBody,
  }) : super(
          message: message ?? 'Validation failed',
          statusCode: 400,
          responseBody: responseBody,
        );
}

/// Thrown when rate-limited (429).
class RateLimitException extends SalesProException {
  final int? retryAfterSeconds;

  RateLimitException({
    String? message,
    this.retryAfterSeconds,
    String? responseBody,
  }) : super(
          message: message ?? 'Rate limit exceeded',
          statusCode: 429,
          responseBody: responseBody,
        );
}

/// Thrown on server-side errors (5xx).
class ServerException extends SalesProException {
  ServerException({
    String? message,
    int? statusCode,
    String? responseBody,
  }) : super(
          message: message ?? 'Internal server error',
          statusCode: statusCode ?? 500,
          responseBody: responseBody,
        );
}

/// Thrown when a network / connectivity issue occurs.
class NetworkException extends SalesProException {
  NetworkException({
    String? message,
    dynamic originalError,
  }) : super(
          message: message ?? 'Network error',
          statusCode: 0,
          originalError: originalError,
        );
}