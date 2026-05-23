/// Useful extensions on Map for SDK-internal parsing.
extension MapExtensions on Map<String, dynamic> {
  /// Get a String value, trying multiple possible keys.
  String? getString(List<String> keys) {
    for (final key in keys) {
      final v = this[key];
      if (v != null) return v.toString();
    }
    return null;
  }

  /// Get a double value, trying multiple possible keys.
  double? getDouble(List<String> keys) {
    for (final key in keys) {
      final v = this[key];
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is String) return double.tryParse(v);
    }
    return null;
  }

  /// Get an int value, trying multiple possible keys.
  int? getInt(List<String> keys) {
    for (final key in keys) {
      final v = this[key];
      if (v is int) return v;
      if (v is String) return int.tryParse(v);
    }
    return null;
  }
}