class AppResponse {
  final bool flag;
  final int code;
  final String message;
  final dynamic data;

  AppResponse({required this.flag, required this.code, required this.message, this.data});

  bool isSuccess() => flag;

  factory AppResponse.fromJson(Map<String, dynamic> json) {
    return AppResponse(
      flag: json['flag'] ?? true,
      code: json['code'],
      message: json['message'],
      data: json['data'],
    );
  }

  AppResponse.error(this.message)
      : code = -1,
        flag = false,
        data = null;
}
