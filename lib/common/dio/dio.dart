import 'package:dio/dio.dart';

final dio = Dio(
  BaseOptions(
    baseUrl: 'https://www.cycdeveloper.com/api/',
    connectTimeout: Duration(seconds: 5),
    receiveTimeout: Duration(seconds: 3),
    headers: {
      'Content-Type': 'application/json',
    },
  ),
);

Future<Response>  loginWithPasswd (String username,String password) async {
  try {
    return await dio.post( // 确保使用正确的 HTTP 方法
      '/auth/loginByPwd', // 检查这个端点是否正确
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