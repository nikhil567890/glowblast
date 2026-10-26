class BusinessInvitation {
  final String id;
  final String businessId;
  final String email;
  final String role;
  final String? token;
  final String? invitedBy;
  final String? invitedByName;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final String status;

  const BusinessInvitation({
    required this.id,
    required this.businessId,
    required this.email,
    required this.role,
    this.token,
    this.invitedBy,
    this.invitedByName,
    this.expiresAt,
    this.createdAt,
    this.status = 'pending',
  });

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  bool get isPending => status == 'pending' && !isExpired;

  factory BusinessInvitation.fromJson(Map<String, dynamic> json) {
    return BusinessInvitation(
      id: json['id']?.toString() ?? '',
      businessId: json['businessId']?.toString() ?? json['business_id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString().toLowerCase() ?? 'staff',
      token: json['token']?.toString(),
      invitedBy: json['invitedBy']?.toString() ?? json['invited_by']?.toString(),
      invitedByName: json['invitedByName']?.toString() ?? json['invited_by_name']?.toString(),
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'].toString())
          : (json['expires_at'] != null ? DateTime.tryParse(json['expires_at'].toString()) : null),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : (json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null),
      status: json['status']?.toString().toLowerCase() ?? 'pending',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'businessId': businessId,
        'email': email,
        'role': role,
        if (token != null) 'token': token,
        if (invitedBy != null) 'invitedBy': invitedBy,
        if (invitedByName != null) 'invitedByName': invitedByName,
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        'status': status,
      };
}
