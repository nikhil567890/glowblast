class Customer {
  final String id;
  final String name;
  final String phone;
  final bool isOptedOut;

  // Marketing WhatsApp Consent (Promotions, discounts, festive blasts)
  final bool hasMarketingConsent;
  final DateTime? marketingConsentRecordedAt;
  final String? marketingConsentSource;
  final String? marketingConsentEvidence;
  final String? marketingConsentTextVersion;

  // Utility WhatsApp Consent (Appointment reminders, booking confirmations, receipts)
  final bool hasUtilityConsent;
  final DateTime? utilityConsentRecordedAt;
  final String? utilityConsentSource;
  final String? utilityConsentEvidence;
  final String? utilityConsentTextVersion;

  final DateTime createdAt;

  Customer({
    required this.id,
    required this.name,
    required this.phone,
    this.isOptedOut = false,
    bool? hasWhatsAppConsent,
    DateTime? consentRecordedAt,
    bool? hasMarketingConsent,
    DateTime? marketingConsentRecordedAt,
    this.marketingConsentSource,
    this.marketingConsentEvidence,
    this.marketingConsentTextVersion,
    this.hasUtilityConsent = false,
    this.utilityConsentRecordedAt,
    this.utilityConsentSource,
    this.utilityConsentEvidence,
    this.utilityConsentTextVersion,
    DateTime? createdAt,
  })  : hasMarketingConsent = hasMarketingConsent ?? hasWhatsAppConsent ?? false,
        marketingConsentRecordedAt = marketingConsentRecordedAt ?? consentRecordedAt,
        createdAt = createdAt ?? DateTime.now();

  /// Backward-compatible getters for existing references
  bool get hasWhatsAppConsent => hasMarketingConsent;
  DateTime? get consentRecordedAt => marketingConsentRecordedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'isOptedOut': isOptedOut,
    'hasWhatsAppConsent': hasMarketingConsent,
    'consentRecordedAt': marketingConsentRecordedAt?.toIso8601String(),
    'hasMarketingConsent': hasMarketingConsent,
    'marketingConsentRecordedAt': marketingConsentRecordedAt?.toIso8601String(),
    'marketingConsentSource': marketingConsentSource,
    'marketingConsentEvidence': marketingConsentEvidence,
    'marketingConsentTextVersion': marketingConsentTextVersion,
    'hasUtilityConsent': hasUtilityConsent,
    'utilityConsentRecordedAt': utilityConsentRecordedAt?.toIso8601String(),
    'utilityConsentSource': utilityConsentSource,
    'utilityConsentEvidence': utilityConsentEvidence,
    'utilityConsentTextVersion': utilityConsentTextVersion,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Customer.fromJson(Map<String, dynamic> json) {
    final hasMarketing = json['hasMarketingConsent'] as bool? ??
        json['hasWhatsAppConsent'] as bool? ??
        false;
    final marketingRecordedAt = json['marketingConsentRecordedAt'] != null
        ? DateTime.tryParse(json['marketingConsentRecordedAt'] as String)
        : (json['consentRecordedAt'] != null
            ? DateTime.tryParse(json['consentRecordedAt'] as String)
            : null);

    return Customer(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      isOptedOut: json['isOptedOut'] as bool? ?? false,
      hasMarketingConsent: hasMarketing,
      marketingConsentRecordedAt: marketingRecordedAt,
      marketingConsentSource: json['marketingConsentSource'] as String?,
      marketingConsentEvidence: json['marketingConsentEvidence'] as String?,
      marketingConsentTextVersion: json['marketingConsentTextVersion'] as String?,
      hasUtilityConsent: json['hasUtilityConsent'] as bool? ?? false,
      utilityConsentRecordedAt: json['utilityConsentRecordedAt'] != null
          ? DateTime.tryParse(json['utilityConsentRecordedAt'] as String)
          : null,
      utilityConsentSource: json['utilityConsentSource'] as String?,
      utilityConsentEvidence: json['utilityConsentEvidence'] as String?,
      utilityConsentTextVersion: json['utilityConsentTextVersion'] as String?,
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
    bool? hasMarketingConsent,
    DateTime? marketingConsentRecordedAt,
    String? marketingConsentSource,
    String? marketingConsentEvidence,
    String? marketingConsentTextVersion,
    bool? hasUtilityConsent,
    DateTime? utilityConsentRecordedAt,
    String? utilityConsentSource,
    String? utilityConsentEvidence,
    String? utilityConsentTextVersion,
    DateTime? createdAt,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      isOptedOut: isOptedOut ?? this.isOptedOut,
      hasMarketingConsent: hasMarketingConsent ?? hasWhatsAppConsent ?? this.hasMarketingConsent,
      marketingConsentRecordedAt: marketingConsentRecordedAt ?? consentRecordedAt ?? this.marketingConsentRecordedAt,
      marketingConsentSource: marketingConsentSource ?? this.marketingConsentSource,
      marketingConsentEvidence: marketingConsentEvidence ?? this.marketingConsentEvidence,
      marketingConsentTextVersion: marketingConsentTextVersion ?? this.marketingConsentTextVersion,
      hasUtilityConsent: hasUtilityConsent ?? this.hasUtilityConsent,
      utilityConsentRecordedAt: utilityConsentRecordedAt ?? this.utilityConsentRecordedAt,
      utilityConsentSource: utilityConsentSource ?? this.utilityConsentSource,
      utilityConsentEvidence: utilityConsentEvidence ?? this.utilityConsentEvidence,
      utilityConsentTextVersion: utilityConsentTextVersion ?? this.utilityConsentTextVersion,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
