/// Represents a Product / Item in the ERP.
class Product {
  final String? id;
  final String? sku;
  final String? name;
  final String? description;
  final double? price;
  final double? cost;
  final String? currency;
  final String? unit;
  final String? category;
  final bool? isActive;
  final int? quantityOnHand;
  final double? weight;
  final Map<String, dynamic>? attributes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Product({
    this.id,
    this.sku,
    this.name,
    this.description,
    this.price,
    this.cost,
    this.currency,
    this.unit,
    this.category,
    this.isActive,
    this.quantityOnHand,
    this.weight,
    this.attributes,
    this.createdAt,
    this.updatedAt,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id']?.toString(),
      sku: json['sku'] ?? json['item_code'],
      name: json['name'] ?? json['item_name'],
      description: json['description'],
      price: _toDouble(json['price'] ?? json['unit_price']),
      cost: _toDouble(json['cost'] ?? json['unit_cost']),
      currency: json['currency'] ?? 'USD',
      unit: json['unit'] ?? json['uom'],
      category: json['category'] ?? json['category_name'],
      isActive: json['is_active'] ?? json['active'],
      quantityOnHand: json['quantity_on_hand'] ?? json['qty'],
      weight: _toDouble(json['weight']),
      attributes: json['attributes'] ?? json['custom_fields'],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'sku': sku,
      'name': name,
      'description': description,
      'price': price,
      'cost': cost,
      'currency': currency,
      'unit': unit,
      'category': category,
      'is_active': isActive,
      if (attributes != null) 'attributes': attributes,
    };
  }

  /// Profit margin (0.0 – 1.0). Returns null if price or cost is missing.
  double? get margin {
    if (price != null && cost != null && price! > 0) {
      return (price! - cost!) / price!;
    }
    return null;
  }

  Product copyWith({
    String? id,
    String? sku,
    String? name,
    String? description,
    double? price,
    double? cost,
    String? currency,
    String? unit,
    String? category,
    bool? isActive,
    int? quantityOnHand,
    double? weight,
    Map<String, dynamic>? attributes,
  }) {
    return Product(
      id: id ?? this.id,
      sku: sku ?? this.sku,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      cost: cost ?? this.cost,
      currency: currency ?? this.currency,
      unit: unit ?? this.unit,
      category: category ?? this.category,
      isActive: isActive ?? this.isActive,
      quantityOnHand: quantityOnHand ?? this.quantityOnHand,
      weight: weight ?? this.weight,
      attributes: attributes ?? this.attributes,
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}