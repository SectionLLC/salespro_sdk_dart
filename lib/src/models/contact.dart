/// Represents a Contact / Customer in the ERP.
class Contact {
  final String? id;
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? phone;
  final String? company;
  final String? address;
  final String? city;
  final String? state;
  final String? zipCode;
  final String? country;
  final String? type; // 'customer', 'vendor', 'lead', etc.
  final String? status;
  final Map<String, dynamic>? customFields;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Contact({
    this.id,
    this.firstName,
    this.lastName,
    this.email,
    this.phone,
    this.company,
    this.address,
    this.city,
    this.state,
    this.zipCode,
    this.country,
    this.type,
    this.status,
    this.customFields,
    this.createdAt,
    this.updatedAt,
  });

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id']?.toString(),
      firstName: json['first_name'] ?? json['firstName'],
      lastName: json['last_name'] ?? json['lastName'],
      email: json['email'],
      phone: json['phone'],
      company: json['company'] ?? json['organization'],
      address: json['address'] ?? json['address1'],
      city: json['city'],
      state: json['state'] ?? json['province'],
      zipCode: json['zip_code'] ?? json['zip'] ?? json['postalCode'],
      country: json['country'],
      type: json['type'] ?? json['contact_type'],
      status: json['status'],
      customFields: json['custom_fields'] ?? json['customFields'],
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
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'phone': phone,
      'company': company,
      'address': address,
      'city': city,
      'state': state,
      'zip_code': zipCode,
      'country': country,
      'type': type,
      'status': status,
      if (customFields != null) 'custom_fields': customFields,
    };
  }

  /// Full display name.
  String get displayName => [firstName, lastName].whereType<String>().join(' ').trim();

  Contact copyWith({
    String? id,
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    String? company,
    String? address,
    String? city,
    String? state,
    String? zipCode,
    String? country,
    String? type,
    String? status,
    Map<String, dynamic>? customFields,
  }) {
    return Contact(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      company: company ?? this.company,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      zipCode: zipCode ?? this.zipCode,
      country: country ?? this.country,
      type: type ?? this.type,
      status: status ?? this.status,
      customFields: customFields ?? this.customFields,
    );
  }
}