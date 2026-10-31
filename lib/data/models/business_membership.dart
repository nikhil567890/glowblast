class BusinessMembership {
  final String businessId;
  final String slug;
  final String displayName;
  final String role;
  final bool isActive;
  final bool productionEnabled;
  final int dailyRecipientLimit;
  final DateTime? joinedAt;

  const BusinessMembership({
    required this.businessId,
    required this.slug,
    required this.displayName,
    this.role = 'member',
    this.isActive = true,
    this.productionEnabled = false,
    this.dailyRecipientLimit = 200,
    this.joinedAt,
  });

  bool get isOwner => role == 'owner';
  bool get isAdmin => role == 'admin' || role == 'owner';
  bool get isStaff => role == 'staff';

  Map<String, dynamic> toJson() => {
        'businessId': businessId,
        'slug': slug,
        'displayName': displayName,
        'role': role,
        'isActive': isActive,
        'productionEnabled': productionEnabled,
        'dailyRecipientLimit': dailyRecipientLimit,
        if (joinedAt != null) 'joinedAt': joinedAt!.toIso8601String(),
      };

  factory BusinessMembership.fromJson(Map<String, dynamic> json) {
    return BusinessMembership(
      businessId: json['businessId']?.toString() ??
          json['business_id']?.toString() ??
          json['id']?.toString() ??
          '',
      slug: json['slug']?.toString() ?? '',
      displayName: json['displayName']?.toString() ??
          json['display_name']?.toString() ??
          json['name']?.toString() ??
          'Business',
      role: json['role']?.toString().toLowerCase() ?? 'staff',
      isActive: json['isActive'] == true || json['is_active'] == true,
      productionEnabled: json['productionEnabled'] == true ||
          json['production_enabled'] == true,
      dailyRecipientLimit: (json['dailyRecipientLimit'] as num?)?.toInt() ??
          (json['daily_recipient_limit'] as num?)?.toInt() ??
          200,
      joinedAt: json['joinedAt'] != null
          ? DateTime.tryParse(json['joinedAt'].toString())
          : (json['joined_at'] != null
              ? DateTime.tryParse(json['joined_at'].toString())
              : null),
    );
  }

  BusinessMembership copyWith({
    String? businessId,
    String? slug,
    String? displayName,
    String? role,
    bool? isActive,
    bool? productionEnabled,
    int? dailyRecipientLimit,
    DateTime? joinedAt,
  }) {
    return BusinessMembership(
      businessId: businessId ?? this.businessId,
      slug: slug ?? this.slug,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      productionEnabled: productionEnabled ?? this.productionEnabled,
      dailyRecipientLimit: dailyRecipientLimit ?? this.dailyRecipientLimit,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BusinessMembership &&
          runtimeType == other.runtimeType &&
          businessId == other.businessId &&
          role == other.role;

  @override
  int get hashCode => businessId.hashCode ^ role.hashCode;
}
