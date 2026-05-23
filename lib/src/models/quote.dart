/// Represents a Quote / Estimate in the ERP.
class Quote {
  final String? id;
  final String? quoteNumber;
  final String? contactId;
  final String? status; // 'draft', 'sent', 'accepted', 'declined', 'expired'
  final DateTime? quoteDate;
  final DateTime? validUntil;
  final double? subtotal;
  final double? taxAmount;
  final double? discountAmount;
  final double? totalAmount;
  final String? notes;
  final List<Map<String, dynamic>>? lineItems;
  final Map<String, dynamic>? customFields;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Quote({
    this.id,
    this.quoteNumber,
    this.contactId,
    this.status,
    this.quoteDate,
    this.validUntil,
    this.subtotal,
    this.taxAmount,
    this.discountAmount,
    this.totalAmount,
    this.notes,
    this.lineItems,
    this.customFields,
    this.createdAt,
    this.updatedAt,
  });

  factory Quote.fromJson(Map<String, dynamic> json) {
    return Quote(
      id: json['id']?.toString(),
      quoteNumber: json['quote_number'] ?? json['number'],
      contactId: json['contact_id']?.toString(),
      status: json['status'],
      quoteDate: json['quote_date'] != null
          ? DateTime.tryParse(json['quote_date'].toString())
          : null,
      validUntil: json['valid_until'] != null
          ? DateTime.tryParse(json['valid_until'].toString())
          : null,
      subtotal: _toDouble(json['subtotal']),
      taxAmount: _toDouble(json['tax_amount']),
      discountAmount: _toDouble(json['discount_amount']),
      totalAmount: _toDouble(json['total_amount'] ?? json['total']),
      notes: json['notes'],
      lineItems: json['line_items'] is List
          ? List<Map<String, dynamic>>.from(json['line_items'])
          : null,
      customFields: json['custom_fields'],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'contact_id': contactId,
        'status': status,
        'quote_date': quoteDate?.toIso8601String(),
        'valid_until': validUntil?.toIso8601String(),
        'notes': notes,
        if (lineItems != null) 'line_items': lineItems,
        if (customFields != null) 'custom_fields': customFields,
      };

  /// Convert the accepted quote into a sales order payload.
  Map<String, dynamic> toOrderPayload() => {
        'contact_id': contactId,
        'line_items': lineItems,
        'notes': notes,
      };

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}