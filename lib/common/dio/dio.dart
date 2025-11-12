import 'package:dio/dio.dart';

final dio = Dio(
  BaseOptions(
    baseUrl: 'https://www.cycdeveloper.com/api/',
    connectTimeout: Duration(seconds: 5),
    receiveTimeout: Duration(seconds: 3),
  ),
);

Future<Response> loginWithPasswd ({required String username,required String password}) async {
  try {
    return await dio.post(
      '/auth/loginByPwd',
      options: Options(
        headers: {
          'Content-Type': 'application/json',
        },
      ),
      data: {
        'username': username,
        'password': password,
      },
    );
    // 处理响应
  } catch (e) {
    print('登录错误: $e');
    rethrow;
  }
}

Future<Response> sendCode ({required String email}) async {
  try {
    return await dio.post(
      '/auth/send-code',
      options: Options(
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      ),
      data: 'email=$email',
    );
    // 处理响应
  } catch (e) {
    print('登录错误: $e');
    rethrow;
  }
}

Future<Response> verifyCode ({required String email,required String code}) async {
  try {
    return await dio.post(
      '/auth/verify-code',
      options: Options(
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      ),
      data: 'email=$email&code=$code',
    );
    // 处理响应
  } catch (e) {
    print('登录错误1: $e');
    rethrow;
  }
}
