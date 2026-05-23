/// Line item inside a sales order.
class OrderLineItem {
  final String? id;
  final String? productId;
  final String? productName;
  final String? sku;
  final double? quantity;
  final double? unitPrice;
  final double? discount;
  final double? total;

  OrderLineItem({
    this.id,
    this.productId,
    this.productName,
    this.sku,
    this.quantity,
    this.unitPrice,
    this.discount,
    this.total,
  });

  factory OrderLineItem.fromJson(Map<String, dynamic> json) {
    return OrderLineItem(
      id: json['id']?.toString(),
      productId: json['product_id']?.toString(),
      productName: json['product_name'] ?? json['name'],
      sku: json['sku'],
      quantity: _toDouble(json['quantity']),
      unitPrice: _toDouble(json['unit_price'] ?? json['price']),
      discount: _toDouble(json['discount']) ?? 0,
      total: _toDouble(json['total'] ?? json['line_total']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'product_id': productId,
        'quantity': quantity,
        'unit_price': unitPrice,
        'discount': discount ?? 0,
      };

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}

/// Represents a Sales Order in the ERP.
class Order {
  final String? id;
  final String? orderNumber;
  final String? contactId;
  final String? status;
  final DateTime? orderDate;
  final DateTime? dueDate;
  final List<OrderLineItem>? lineItems;
  final double? subtotal;
  final double? taxAmount;
  final double? discountAmount;
  final double? totalAmount;
  final String? notes;
  final Map<String, dynamic>? customFields;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Order({
    this.id,
    this.orderNumber,
    this.contactId,
    this.status,
    this.orderDate,
    this.dueDate,
    this.lineItems,
    this.subtotal,
    this.taxAmount,
    this.discountAmount,
    this.totalAmount,
    this.notes,
    this.customFields,
    this.createdAt,
    this.updatedAt,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id']?.toString(),
      orderNumber: json['order_number'] ?? json['number'],
      contactId: json['contact_id']?.toString(),
      status: json['status'],
      orderDate: json['order_date'] != null
          ? DateTime.tryParse(json['order_date'].toString())
          : null,
      dueDate: json['due_date'] != null
          ? DateTime.tryParse(json['due_date'].toString())
          : null,
      lineItems: (json['line_items'] ?? json['items']) is List
          ? (json['line_items'] ?? json['items'])
              .map<OrderLineItem>((e) => OrderLineItem.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
      subtotal: _toDouble(json['subtotal']),
      taxAmount: _toDouble(json['tax_amount'] ?? json['tax']),
      discountAmount: _toDouble(json['discount_amount'] ?? json['discount']),
      totalAmount: _toDouble(json['total_amount'] ?? json['total']),
      notes: json['notes'],
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
        'order_date': orderDate?.toIso8601String(),
        'due_date': dueDate?.toIso8601String(),
        'line_items': lineItems?.map((e) => e.toJson()).toList(),
        'notes': notes,
        if (customFields != null) 'custom_fields': customFields,
      };

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}