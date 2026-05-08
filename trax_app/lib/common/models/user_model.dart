class LoginModel {
  User? user;
  String? accessToken;
  String? refreshToken;
  String? tokenType;
  int? expiresIn;

  LoginModel({this.user, this.accessToken, this.refreshToken, this.tokenType, this.expiresIn});

  factory LoginModel.fromJson(Map<String, dynamic> json) => LoginModel(
    user: json["user"] == null ? null : User.fromJson(json["user"]),
    accessToken: json["accessToken"],
    refreshToken: json["refreshToken"],
    tokenType: json["tokenType"],
    expiresIn: json["expiresIn"],
  );
}

class User {
  DateTime? createdAt;
  String? avatarUrl;
  int? id;
  String? email;
  String? username;

  User({this.createdAt, this.avatarUrl, this.id, this.email, this.username});

  factory User.fromJson(Map<String, dynamic> json) => User(
    createdAt: json["createdAt"] == null ? null : DateTime.parse(json["createdAt"]),
    avatarUrl: json["avatarUrl"],
    id: json["id"],
    email: json["email"],
    username: json["username"],
  );

  String toJson() {
    return '{"avatarUrl": "$avatarUrl", "id": $id, "email": "$email", "username": "$username"}';
  }
}
