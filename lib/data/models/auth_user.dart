class AuthUser {
  final String id;
  final String name;
  final String email;
  final String? businessName;
  final String? phone;
  final bool emailVerified;

  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.businessName,
    this.phone,
    this.emailVerified = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        if (businessName != null) 'businessName': businessName,
        if (phone != null) 'phone': phone,
        'emailVerified': emailVerified,
      };

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      businessName: json['businessName'] as String?,
      phone: json['phone'] as String?,
      emailVerified: json['emailVerified'] as bool? ?? true,
    );
  }
}
