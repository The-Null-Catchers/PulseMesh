class WorkspaceSummary {
  const WorkspaceSummary({
    required this.id,
    required this.name,
    required this.slug,
    required this.role,
    this.avatarUrl,
    this.description,
  });

  final String id;
  final String name;
  final String slug;
  final String role;
  final String? avatarUrl;
  final String? description;

  factory WorkspaceSummary.fromJson(Map<String, dynamic> json) {
    return WorkspaceSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      role: json['role'] as String? ?? 'Member',
      avatarUrl: json['avatar_url'] as String?,
      description: json['description'] as String?,
    );
  }
}
