/// Standard API response wrapper.
class ApiResponse {
  final bool success;
  final int statusCode;
  final dynamic data;
  final String? message;

  ApiResponse({
    required this.success,
    required this.statusCode,
    this.data,
    this.message,
  });

  /// The paginated list of items (when [data] is a Map with 'items' / 'data').
  List<T> items<T>(T Function(Map<String, dynamic>) fromJson) {
    final raw = data;
    if (raw is Map) {
      final list = raw['items'] ?? raw['data'] ?? raw['results'];
      if (list is List) {
        return list.map((e) => fromJson(e as Map<String, dynamic>)).toList();
      }
    }
    if (raw is List) {
      return raw.map((e) => fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  /// Pagination metadata.
  PaginationMeta? get pagination {
    if (data is Map) {
      final map = data as Map;
      if (map.containsKey('meta') || map.containsKey('pagination')) {
        final p = map['meta'] ?? map['pagination'];
        if (p is Map) {
          return PaginationMeta.fromJson(Map<String, dynamic>.from(p));
        }
      }
    }
    return null;
  }

  @override
  String toString() => 'ApiResponse(success: $success, statusCode: $statusCode)';
}

/// Pagination metadata returned by list endpoints.
class PaginationMeta {
  final int currentPage;
  final int totalPages;
  final int totalItems;
  final int perPage;

  PaginationMeta({
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
    required this.perPage,
  });

  factory PaginationMeta.fromJson(Map<String, dynamic> json) {
    return PaginationMeta(
      currentPage: json['current_page'] ?? json['page'] ?? 1,
      totalPages: json['total_pages'] ?? json['last_page'] ?? 1,
      totalItems: json['total'] ?? json['total_items'] ?? 0,
      perPage: json['per_page'] ?? json['limit'] ?? 25,
    );
  }
}