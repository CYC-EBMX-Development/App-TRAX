import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:tra_x/common/utils/trax_log_util.dart';
import 'app_logger_interceptor.dart';
import 'app_response.dart';

class TraxUrl {
  TraxUrl._();

  static const String baseUrl = 'https://www.cycdeveloper.com/api/';
  static const String loginWithPasswd = '/auth/loginByPwd';
}

class TraxApi {
  TraxApi._();

  static late Dio _dio;

  static void init() {
    _dio = Dio(
      BaseOptions(
        baseUrl: TraxUrl.baseUrl,
        connectTimeout: Duration(seconds: 5),
        receiveTimeout: Duration(seconds: 3),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        responseType: ResponseType.json,
      ),
    );
    _dio.interceptors.addAll(
      [
        AppLoggerInterceptor(
          requestBody: true,
          requestHeader: false,
          responseBody: true,
          responseHeader: false,
          logPrint: (msg) => TraxLogUtil.debug(msg.toString()),
          enabled: kDebugMode,
        ),
      ],
    );
  }

  static Future<AppResponse> loginWithPasswd({
    required String username,
    required String password,
  }) async {
    try {
      Response response = await _dio.post(
        TraxUrl.loginWithPasswd,
        options: Options(headers: {'Content-Type': 'application/json'}),
        data: {'username': username, 'password': password},
      );
      return AppResponse.fromJson(response.data);
    } catch (e) {
      return AppResponse.error(e.toString());
    }
  }

  static Future<AppResponse> sendCode({required String email}) async {
    try {
      Response response = await _dio.post('/auth/send-code', data: 'email=$email');
      return AppResponse.fromJson(response.data);
    } catch (e) {
      return AppResponse.error(e.toString());
    }
  }

  static Future<AppResponse> verifyCode({required String email, required String code}) async {
    try {
      Response response = await _dio.post('/auth/verify-code', data: 'email=$email&code=$code');
      return AppResponse.fromJson(response.data);
    } catch (e) {
      return AppResponse.error(e.toString());
    }
  }
}
