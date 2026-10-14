class Customer {
  final String id;
  final String name;
  final String phone;
  final bool isOptedOut;
  final bool hasWhatsAppConsent;
  final DateTime? consentRecordedAt;
  final DateTime createdAt;

  Customer({
    required this.id,
    required this.name,
    required this.phone,
    this.isOptedOut = false,
    this.hasWhatsAppConsent = false,
    this.consentRecordedAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'isOptedOut': isOptedOut,
    'hasWhatsAppConsent': hasWhatsAppConsent,
    'consentRecordedAt': consentRecordedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      isOptedOut: json['isOptedOut'] as bool? ?? false,
      hasWhatsAppConsent: json['hasWhatsAppConsent'] as bool? ?? false,
      consentRecordedAt: json['consentRecordedAt'] != null
          ? DateTime.tryParse(json['consentRecordedAt'] as String)
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Customer copyWith({
    String? id,
    String? name,
    String? phone,
    bool? isOptedOut,
    bool? hasWhatsAppConsent,
    DateTime? consentRecordedAt,
    DateTime? createdAt,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      isOptedOut: isOptedOut ?? this.isOptedOut,
      hasWhatsAppConsent: hasWhatsAppConsent ?? this.hasWhatsAppConsent,
      consentRecordedAt: consentRecordedAt ?? this.consentRecordedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
