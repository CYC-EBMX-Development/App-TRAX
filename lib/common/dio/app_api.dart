import 'package:dio/dio.dart';
import 'app_response.dart';

final dio = Dio(
  BaseOptions(
    baseUrl: 'https://www.cycdeveloper.com/api/',
    connectTimeout: Duration(seconds: 5),
    receiveTimeout: Duration(seconds: 3),
  ),
);

//
Future<AppResponse> loginWithPasswd ({required String username,required String password}) async {
  try {
    Response response = await dio.post(
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
    return AppResponse.fromJson(response.data);
  } catch (e) {
    return AppResponse.error(e.toString());
  }
}

//
Future<AppResponse> sendCode ({required String email}) async {
  try {
    Response response = await dio.post(
      '/auth/send-code',
      options: Options(
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      ),
      data: 'email=$email',
    );
    return AppResponse.fromJson(response.data);
  } catch (e) {
    return AppResponse.error(e.toString());
  }
}

//
Future<AppResponse> verifyCode ({required String email,required String code}) async {
  try {
    Response response = await dio.post(
      '/auth/verify-code',
      options: Options(
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      ),
      data: 'email=$email&code=$code',
    );
    return AppResponse.fromJson(response.data);
  } catch (e) {
    return AppResponse.error(e.toString());
  }
}
