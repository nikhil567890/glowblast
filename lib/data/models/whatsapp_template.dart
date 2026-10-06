class WhatsAppTemplate {
  final String id;
  final String name; // Meta template name (e.g. 'birthday_offer', 'hello_world')
  final String displayName; // Local display name (e.g. 'Birthday Pampering')
  final String? description;
  final String category; // 'MARKETING', 'UTILITY', 'AUTHENTICATION'
  final String language; // 'en_US'
  final String status; // 'draft', 'pending_approval', 'approved', 'rejected', 'disabled'
  final String metaStatus; // 'APPROVED', 'PENDING', 'REJECTED', 'PAUSED', 'DISABLED', 'NOT_SUBMITTED'
  final String? metaTemplateId;
  final String body; // Text with {name}, {business_name}
  final List<String> variables;
  final Map<String, String>? exampleValues;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastSyncedAt;

  WhatsAppTemplate({
    required this.id,
    required this.name,
    required this.displayName,
    this.description,
    this.category = 'MARKETING',
    this.language = 'en_US',
    this.status = 'draft',
    this.metaStatus = 'NOT_SUBMITTED',
    this.metaTemplateId,
    required this.body,
    this.variables = const [],
    this.exampleValues,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.lastSyncedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isApproved => status.toLowerCase() == 'approved';
  bool get canSend => isApproved;
  bool get isPending => status.toLowerCase() == 'pending_approval';
  bool get isDraft => status.toLowerCase() == 'draft';
  bool get isRejected => status.toLowerCase() == 'rejected';

  // Convenience aliases for Meta compatibility
  String get metaTemplateName => name;
  String get metaLanguage => language;
  String get approvalStatus => status;
  String get localBody => body;

  /// Resolves the local body text with sample or actual recipient and business names.
  String resolvePreview({
    String customerName = 'Valued Customer',
    String businessName = 'Glow Spa',
    Map<String, String>? customValues,
  }) {
    String resolved = body;
    resolved = resolved.replaceAll('{name}', customerName);
    resolved = resolved.replaceAll('{customer_name}', customerName);
    resolved = resolved.replaceAll('{client}', customerName);
    resolved = resolved.replaceAll('{business_name}', businessName);
    resolved = resolved.replaceAll('{spa_name}', businessName);

    if (customValues != null) {
      customValues.forEach((key, val) {
        resolved = resolved.replaceAll('{$key}', val);
      });
    }

    if (exampleValues != null) {
      exampleValues!.forEach((key, val) {
        resolved = resolved.replaceAll('{$key}', val);
      });
    }

    return resolved;
  }

  /// Maps local {variables} to Meta's numbered format {{1}}, {{2}}.
  Map<String, String> getMetaParameterMapping() {
    final Map<String, String> mapping = {};
    for (int i = 0; i < variables.length; i++) {
      mapping[variables[i]] = '{{${i + 1}}}';
    }
    return mapping;
  }

  /// Returns message body in Meta template format with {{1}}, {{2}} parameters.
  String getMetaNumberedBody() {
    String metaBody = body;
    for (int i = 0; i < variables.length; i++) {
      final v = variables[i];
      metaBody = metaBody.replaceAll('{$v}', '{{${i + 1}}}');
    }
    return metaBody;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'displayName': displayName,
        'description': description,
        'category': category,
        'language': language,
        'status': status,
        'metaStatus': metaStatus,
        'metaTemplateId': metaTemplateId,
        'body': body,
        'variables': variables,
        'exampleValues': exampleValues,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      };

  factory WhatsAppTemplate.fromJson(Map<String, dynamic> json) {
    return WhatsAppTemplate(
      id: json['id'] as String? ?? 'tpl_${json['name'] ?? 'custom'}',
      name: json['name'] as String? ?? '',
      displayName: json['displayName'] as String? ?? json['name'] as String? ?? 'Template',
      description: json['description'] as String?,
      category: json['category'] as String? ?? 'MARKETING',
      language: json['language'] as String? ?? 'en_US',
      status: json['status'] as String? ?? 'draft',
      metaStatus: json['metaStatus'] as String? ?? 'NOT_SUBMITTED',
      metaTemplateId: json['metaTemplateId'] as String?,
      body: json['body'] as String? ?? '',
      variables: (json['variables'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      exampleValues: (json['exampleValues'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v.toString()),
      ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      lastSyncedAt: json['lastSyncedAt'] != null
          ? DateTime.tryParse(json['lastSyncedAt'] as String)
          : null,
    );
  }

  WhatsAppTemplate copyWith({
    String? id,
    String? name,
    String? displayName,
    String? description,
    String? category,
    String? language,
    String? status,
    String? metaStatus,
    String? metaTemplateId,
    String? body,
    List<String>? variables,
    Map<String, String>? exampleValues,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSyncedAt,
  }) {
    return WhatsAppTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      description: description ?? this.description,
      category: category ?? this.category,
      language: language ?? this.language,
      status: status ?? this.status,
      metaStatus: metaStatus ?? this.metaStatus,
      metaTemplateId: metaTemplateId ?? this.metaTemplateId,
      body: body ?? this.body,
      variables: variables ?? this.variables,
      exampleValues: exampleValues ?? this.exampleValues,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}
