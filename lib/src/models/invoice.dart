/// Represents an Invoice in the ERP.
class Invoice {
  final String? id;
  final String? invoiceNumber;
  final String? orderId;
  final String? contactId;
  final String? status; // 'draft', 'sent', 'paid', 'overdue', 'cancelled'
  final DateTime? invoiceDate;
  final DateTime? dueDate;
  final DateTime? paidDate;
  final double? subtotal;
  final double? taxAmount;
  final double? discountAmount;
  final double? totalAmount;
  final double? amountPaid;
  final double? amountDue;
  final String? notes;
  final List<Map<String, dynamic>>? lineItems;
  final Map<String, dynamic>? customFields;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Invoice({
    this.id,
    this.invoiceNumber,
    this.orderId,
    this.contactId,
    this.status,
    this.invoiceDate,
    this.dueDate,
    this.paidDate,
    this.subtotal,
    this.taxAmount,
    this.discountAmount,
    this.totalAmount,
    this.amountPaid,
    this.amountDue,
    this.notes,
    this.lineItems,
    this.customFields,
    this.createdAt,
    this.updatedAt,
  });

  factory Invoice.fromJson(Map<String, dynamic> json) {
    return Invoice(
      id: json['id']?.toString(),
      invoiceNumber: json['invoice_number'] ?? json['number'],
      orderId: json['order_id']?.toString(),
      contactId: json['contact_id']?.toString(),
      status: json['status'],
      invoiceDate: json['invoice_date'] != null
          ? DateTime.tryParse(json['invoice_date'].toString())
          : null,
      dueDate: json['due_date'] != null
          ? DateTime.tryParse(json['due_date'].toString())
          : null,
      paidDate: json['paid_date'] != null
          ? DateTime.tryParse(json['paid_date'].toString())
          : null,
      subtotal: _toDouble(json['subtotal']),
      taxAmount: _toDouble(json['tax_amount']),
      discountAmount: _toDouble(json['discount_amount']),
      totalAmount: _toDouble(json['total_amount'] ?? json['total']),
      amountPaid: _toDouble(json['amount_paid']),
      amountDue: _toDouble(json['amount_due'] ?? json['balance']),
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
        'order_id': orderId,
        'contact_id': contactId,
        'status': status,
        'invoice_date': invoiceDate?.toIso8601String(),
        'due_date': dueDate?.toIso8601String(),
        'notes': notes,
        if (lineItems != null) 'line_items': lineItems,
        if (customFields != null) 'custom_fields': customFields,
      };

  /// Whether the invoice is fully paid.
  bool get isPaid => status == 'paid' || (amountDue != null && amountDue! <= 0);

  /// Whether the invoice is overdue.
  bool get isOverdue =>
      status == 'overdue' ||
      (dueDate != null && dueDate!.isBefore(DateTime.now()) && !isPaid);

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}