class BusinessMember {
  final String businessId;
  final String userId;
  final String role;
  final DateTime? joinedAt;
  final String? name;
  final String? email;

  const BusinessMember({
    required this.businessId,
    required this.userId,
    required this.role,
    this.joinedAt,
    this.name,
    this.email,
  });

  bool get isOwner => role == 'owner';
  bool get isAdmin => role == 'admin' || role == 'owner';
  bool get isStaff => role == 'staff';

  String get displayName {
    if (name != null && name!.trim().isNotEmpty) {
      return name!.trim();
    }
    if (email != null && email!.trim().isNotEmpty) {
      return email!.split('@').first;
    }
    return 'User';
  }

  factory BusinessMember.fromJson(Map<String, dynamic> json) {
    return BusinessMember(
      businessId: json['businessId']?.toString() ?? json['business_id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
      role: json['role']?.toString().toLowerCase() ?? 'staff',
      joinedAt: json['joinedAt'] != null
          ? DateTime.tryParse(json['joinedAt'].toString())
          : (json['joined_at'] != null ? DateTime.tryParse(json['joined_at'].toString()) : null),
      name: json['name']?.toString() ?? json['displayName']?.toString(),
      email: json['email']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'businessId': businessId,
        'userId': userId,
        'role': role,
        if (joinedAt != null) 'joinedAt': joinedAt!.toIso8601String(),
        if (name != null) 'name': name,
        if (email != null) 'email': email,
      };
}
