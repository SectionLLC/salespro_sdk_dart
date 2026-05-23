/// Generic report data returned by the ERP.
class Report {
  final String? id;
  final String? name;
  final String? type;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final Map<String, dynamic>? summary;
  final List<Map<String, dynamic>>? rows;
  final Map<String, dynamic>? metadata;
  final DateTime? generatedAt;

  Report({
    this.id,
    this.name,
    this.type,
    this.dateFrom,
    this.dateTo,
    this.summary,
    this.rows,
    this.metadata,
    this.generatedAt,
  });

  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      id: json['id']?.toString(),
      name: json['name'] ?? json['title'],
      type: json['type'] ?? json['report_type'],
      dateFrom: json['date_from'] != null
          ? DateTime.tryParse(json['date_from'].toString())
          : null,
      dateTo: json['date_to'] != null
          ? DateTime.tryParse(json['date_to'].toString())
          : null,
      summary: json['summary'] ?? json['totals'],
      rows: json['rows'] is List
          ? List<Map<String, dynamic>>.from(json['rows'])
          : null,
      metadata: json['metadata'],
      generatedAt: json['generated_at'] != null
          ? DateTime.tryParse(json['generated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'date_from': dateFrom?.toIso8601String(),
        'date_to': dateTo?.toIso8601String(),
      };
}

/// Sales summary report.
class SalesSummary {
  final double? totalRevenue;
  final double? totalCost;
  final double? totalProfit;
  final int? totalOrders;
  final int? totalInvoices;
  final double? averageOrderValue;

  SalesSummary({
    this.totalRevenue,
    this.totalCost,
    this.totalProfit,
    this.totalOrders,
    this.totalInvoices,
    this.averageOrderValue,
  });

  factory SalesSummary.fromJson(Map<String, dynamic> json) {
    return SalesSummary(
      totalRevenue: _toDouble(json['total_revenue'] ?? json['revenue']),
      totalCost: _toDouble(json['total_cost'] ?? json['cost']),
      totalProfit: _toDouble(json['total_profit'] ?? json['profit']),
      totalOrders: json['total_orders'] ?? json['order_count'],
      totalInvoices: json['total_invoices'] ?? json['invoice_count'],
      averageOrderValue: _toDouble(json['average_order_value'] ?? json['aov']),
    );
  }

  /// Profit margin as a ratio (0.0 – 1.0).
  double? get margin {
    if (totalRevenue != null && totalRevenue! > 0 && totalProfit != null) {
      return totalProfit! / totalRevenue!;
    }
    return null;
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}