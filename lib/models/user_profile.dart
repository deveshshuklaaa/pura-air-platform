class UserProfile {
  final String displayName;
  final String phone;
  final String location;
  final String about;

  const UserProfile({
    required this.displayName,
    required this.phone,
    required this.location,
    required this.about,
  });

  static UserProfile empty() {
    return const UserProfile(
      displayName: '',
      phone: '',
      location: '',
      about: '',
    );
  }

  UserProfile copyWith({
    String? displayName,
    String? phone,
    String? location,
    String? about,
  }) {
    return UserProfile(
      displayName: displayName ?? this.displayName,
      phone: phone ?? this.phone,
      location: location ?? this.location,
      about: about ?? this.about,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'display_name': displayName,
      'phone': phone,
      'location': location,
      'about': about,
    };
  }

  static UserProfile fromMap(Map<String, dynamic>? data) {
    if (data == null) return UserProfile.empty();
    return UserProfile(
      displayName: (data['display_name'] as String?) ?? '',
      phone: (data['phone'] as String?) ?? '',
      location: (data['location'] as String?) ?? '',
      about: (data['about'] as String?) ?? '',
    );
  }
}
