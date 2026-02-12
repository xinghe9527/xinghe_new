import 'user.dart';

class AuthState {
  final User? user;
  final String? token;
  final bool isAuthenticated;

  AuthState({
    this.user,
    this.token,
    this.isAuthenticated = false,
  });

  factory AuthState.initial() {
    return AuthState(
      user: null,
      token: null,
      isAuthenticated: false,
    );
  }

  factory AuthState.authenticated({
    required User user,
    required String token,
  }) {
    return AuthState(
      user: user,
      token: token,
      isAuthenticated: true,
    );
  }

  factory AuthState.fromJson(Map<String, dynamic> json) {
    return AuthState(
      user: json['user'] != null ? User.fromJson(json['user']) : null,
      token: json['token'],
      isAuthenticated: json['isAuthenticated'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user': user?.toJson(),
      'token': token,
      'isAuthenticated': isAuthenticated,
    };
  }

  AuthState copyWith({
    User? user,
    String? token,
    bool? isAuthenticated,
  }) {
    return AuthState(
      user: user ?? this.user,
      token: token ?? this.token,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    );
  }
}
