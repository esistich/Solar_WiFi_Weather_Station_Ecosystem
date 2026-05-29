/// Angemeldeter Benutzer (JWT-Auth gegen Node.js-Backend).
class AppUser {
  final String id;
  final String email;
  final String token; // JWT

  const AppUser({
	required this.id,
	required this.email,
	required this.token,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
		id: json['id'] as String,
		email: json['email'] as String,
		token: json['token'] as String,
	  );

  Map<String, dynamic> toJson() => {
		'id': id,
		'email': email,
		'token': token,
	  };
}
