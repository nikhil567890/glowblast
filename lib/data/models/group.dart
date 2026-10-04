class CustomerGroup {
  final String id;
  final String name;
  final String description;
  final List<String> customerIds;
  final bool isSystemGroup;

  CustomerGroup({
    required this.id,
    required this.name,
    this.description = '',
    required this.customerIds,
    this.isSystemGroup = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'customerIds': customerIds,
    'isSystemGroup': isSystemGroup,
  };

  factory CustomerGroup.fromJson(Map<String, dynamic> json) {
    return CustomerGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      customerIds: (json['customerIds'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [],
      isSystemGroup: json['isSystemGroup'] as bool? ?? false,
    );
  }

  CustomerGroup copyWith({
    String? id,
    String? name,
    String? description,
    List<String>? customerIds,
    bool? isSystemGroup,
  }) {
    return CustomerGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      customerIds: customerIds ?? List.from(this.customerIds),
      isSystemGroup: isSystemGroup ?? this.isSystemGroup,
    );
  }
}
