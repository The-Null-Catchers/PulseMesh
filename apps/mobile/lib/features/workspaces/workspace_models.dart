class WorkspaceSummary {
  const WorkspaceSummary({
    required this.id,
    required this.name,
    required this.slug,
    required this.avatarUrl,
    required this.description,
    required this.role,
  });

  final String id;
  final String name;
  final String slug;
  final String? avatarUrl;
  final String? description;
  final String role;

  factory WorkspaceSummary.fromJson(Map<String, dynamic> json) {
    return WorkspaceSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      description: json['description'] as String?,
      role: json['role'] as String? ?? 'Member',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        'avatar_url': avatarUrl,
        'description': description,
        'role': role,
      };
}
