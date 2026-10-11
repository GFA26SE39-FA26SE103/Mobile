class AuthUser {
  const AuthUser({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.role,
    required this.status,
  });

  final String userId;
  final String email;
  final String fullName;
  final String role;
  final String status;

  bool get isStaff => role == 'STAFF';
  bool get isActive => status == 'ACTIVE';

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return email.isEmpty ? '?' : email[0].toUpperCase();
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        userId: json['userId'] as String,
        email: json['email'] as String,
        fullName: (json['fullName'] as String?) ?? '',
        role: json['role'] as String,
        status: json['status'] as String,
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'email': email,
        'fullName': fullName,
        'role': role,
        'status': status,
      };
}

class AuthSession {
  const AuthSession({required this.accessToken, required this.expiresAt, required this.user});

  final String accessToken;
  final DateTime expiresAt;
  final AuthUser user;

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now);

  AuthSession withUser(AuthUser next) => AuthSession(accessToken: accessToken, expiresAt: expiresAt, user: next);

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: json['accessToken'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'expiresAt': expiresAt.toIso8601String(),
        'user': user.toJson(),
      };
}

/// Why sign-in failed, phrased for the person holding the phone.
class SignInFailure implements Exception {
  const SignInFailure(this.message);
  final String message;

  @override
  String toString() => message;
}
