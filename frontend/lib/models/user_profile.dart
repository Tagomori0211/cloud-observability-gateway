class UserProfile {
  final int id;
  final String misskeyId;
  final String misskeyHost;
  final String username;

  UserProfile({
    required this.id,
    required this.misskeyId,
    required this.misskeyHost,
    required this.username,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as int,
      misskeyId: json['misskeyId'] as String,
      misskeyHost: json['misskeyHost'] as String,
      username: json['username'] as String,
    );
  }
}
