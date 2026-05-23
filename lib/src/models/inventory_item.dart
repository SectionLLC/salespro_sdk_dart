/// Inventory stock information for a product.
class InventoryItem {
  final String? id;
  final String? productId;
  final String? sku;
  final String? warehouse;
  final int? quantityOnHand;
  final int? quantityAllocated;
  final int? quantityAvailable;
  final int? reorderPoint;
  final int? reorderQuantity;
  final String? binLocation;
  final DateTime? lastCountDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  InventoryItem({
    this.id,
    this.productId,
    this.sku,
    this.warehouse,
    this.quantityOnHand,
    this.quantityAllocated,
    this.quantityAvailable,
    this.reorderPoint,
    this.reorderQuantity,
    this.binLocation,
    this.lastCountDate,
    this.createdAt,
    this.updatedAt,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: json['id']?.toString(),
      productId: json['product_id']?.toString(),
      sku: json['sku'],
      warehouse: json['warehouse'] ?? json['warehouse_name'],
      quantityOnHand: json['quantity_on_hand'] ?? json['qty_on_hand'],
      quantityAllocated: json['quantity_allocated'] ?? json['qty_allocated'],
      quantityAvailable: json['quantity_available'] ?? json['qty_available'],
      reorderPoint: json['reorder_point'],
      reorderQuantity: json['reorder_quantity'],
      binLocation: json['bin_location'] ?? json['location'],
      lastCountDate: json['last_count_date'] != null
          ? DateTime.tryParse(json['last_count_date'].toString())
          : null,
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
        'product_id': productId,
        'warehouse': warehouse,
        'quantity_on_hand': quantityOnHand,
        'quantity_allocated': quantityAllocated,
        'reorder_point': reorderPoint,
        'reorder_quantity': reorderQuantity,
        'bin_location': binLocation,
      };

  /// Whether stock is below the reorder point.
  bool get needsReorder {
    if (quantityOnHand != null && reorderPoint != null) {
      return quantityOnHand! <= reorderPoint!;
    }
    return false;
  }
}