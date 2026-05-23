/// Represents a pending operation in the sync queue.
class SyncQueueItem {
  final String? id;
  final String entityType;   // 'contact', 'product', 'order', etc.
  final String entityId;     // The entity's ID
  final String operation;    // 'create', 'update', 'delete'
  final String path;         // API endpoint path
  final String? body;        // JSON-encoded request body
  final String? headers;     // JSON-encoded extra headers
  final int attempts;
  final int maxAttempts;
  final DateTime createdAt;
  final DateTime? lastAttemptAt;
  final String status;       // 'pending', 'in_progress', 'failed', 'completed'

  SyncQueueItem({
    this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.path,
    this.body,
    this.headers,
    this.attempts = 0,
    this.maxAttempts = 5,
    DateTime? createdAt,
    this.lastAttemptAt,
    this.status = 'pending',
  }) : createdAt = createdAt ?? DateTime.now();

  factory SyncQueueItem.fromMap(Map<String, dynamic> map) {
    return SyncQueueItem(
      id: map['id'] as String?,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as String,
      operation: map['operation'] as String,
      path: map['path'] as String,
      body: map['body'] as String?,
      headers: map['headers'] as String?,
      attempts: map['attempts'] as int? ?? 0,
      maxAttempts: map['max_attempts'] as int? ?? 5,
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int)
          : DateTime.now(),
      lastAttemptAt: map['last_attempt_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_attempt_at'] as int)
          : null,
      status: map['status'] as String? ?? 'pending',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'operation': operation,
      'path': path,
      'body': body,
      'headers': headers,
      'attempts': attempts,
      'max_attempts': maxAttempts,
      'created_at': createdAt.millisecondsSinceEpoch,
      'last_attempt_at': lastAttemptAt?.millisecondsSinceEpoch,
      'status': status,
    };
  }

  SyncQueueItem copyWith({
    String? id,
    String? entityType,
    String? entityId,
    String? operation,
    String? path,
    String? body,
    String? headers,
    int? attempts,
    int? maxAttempts,
    DateTime? createdAt,
    DateTime? lastAttemptAt,
    String? status,
  }) {
    return SyncQueueItem(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      path: path ?? this.path,
      body: body ?? this.body,
      headers: headers ?? this.headers,
      attempts: attempts ?? this.attempts,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      createdAt: createdAt ?? this.createdAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      status: status ?? this.status,
    );
  }

  /// Whether this item has exceeded its maximum retry attempts.
  bool get isExhausted => attempts >= maxAttempts;

  /// Whether this item is eligible for processing.
  bool get isPending => status == 'pending' && !isExhausted;
}