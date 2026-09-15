class UserProfile {
  const UserProfile({
    this.name = '',
    this.style = '',
    this.format = '',
    this.constraints = '',
  });

  final String name;
  final String style;
  final String format;
  final String constraints;

  bool get isEmpty =>
      name.isEmpty && style.isEmpty && format.isEmpty && constraints.isEmpty;

  Map<String, String> toJson() => {
        if (name.isNotEmpty) 'name': name,
        if (style.isNotEmpty) 'style': style,
        if (format.isNotEmpty) 'format': format,
        if (constraints.isNotEmpty) 'constraints': constraints,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        name: json['name'] as String? ?? '',
        style: json['style'] as String? ?? '',
        format: json['format'] as String? ?? '',
        constraints: json['constraints'] as String? ?? '',
      );
}
