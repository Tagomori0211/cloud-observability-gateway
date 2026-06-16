class LinkedAccount {
  final int id;
  final int userId;
  final String edition; // 'java' | 'bedrock'
  final String ign;
  final String? externalId;
  final DateTime linkedAt;

  LinkedAccount({
    required this.id,
    required this.userId,
    required this.edition,
    required this.ign,
    this.externalId,
    required this.linkedAt,
  });

  factory LinkedAccount.fromJson(Map<String, dynamic> json) {
    return LinkedAccount(
      id: json['id'] as int,
      userId: json['userId'] as int,
      edition: json['edition'] as String,
      ign: json['ign'] as String,
      externalId: json['externalId'] as String?,
      linkedAt: DateTime.parse(json['linkedAt'] as String),
    );
  }
}
