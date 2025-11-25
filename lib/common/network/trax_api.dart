import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:tra_x/common/utils/trax_log_util.dart';
import 'package:tra_x/common/widgets/trax_dialog.dart';
import 'app_logger_interceptor.dart';
import 'app_response.dart';

class TraxUrl {
  TraxUrl._();

  static const String baseUrlRelease = 'https://www.cycdeveloper.com';
  static const String baseUrlDebug = 'http://192.168.10.65:18089';
  static const String baseUrlDebugNoPort = 'http://192.168.10.65';
  static const String loginWithPasswd = '/api/auth/loginByPwd';
  static const String sendCode = '/api/auth/send-code';
  static const String verifyCode = '/api/auth/verify-code';
  static const String registerByPwd = '/api/auth/registerByPwd';
  static const String loginWithGoogle = '/oauth2/authorization/google';
  static const String loginWithFacebook = '/oauth2/authorization/facebook';
  static const String loginWithApple = '/oauth2/authorization/apple';
  static const String loginWithGithub = '/oauth2/authorization/github';
}

class _TraxContentType {
  static const String json = 'application/json';
  static const String form = 'application/x-www-form-urlencoded';
}

class TraxApi {
  TraxApi._();

  static late Dio _dio;

  static late bool _isDebug;

  static void init({required bool isDebug}) {
    _isDebug = isDebug;
    _dio = Dio(
      BaseOptions(
        baseUrl: isDebug ? TraxUrl.baseUrlDebug : TraxUrl.baseUrlRelease,
        connectTimeout: Duration(seconds: 5),
        receiveTimeout: Duration(seconds: 3),
        headers: {'Content-Type': _TraxContentType.form},
        responseType: ResponseType.json,
      ),
    );
    _dio.interceptors.addAll([
      AppLoggerInterceptor(
        requestBody: true,
        requestHeader: false,
        responseBody: true,
        responseHeader: false,
        logPrint: (msg) => TraxLogUtil.debug(msg.toString()),
        enabled: kDebugMode,
      ),
    ]);
  }

  /// POST Method
  ///
  /// with loading, default: true
  static Future<AppResponse> post(
    String url, {
    required Map<String, dynamic> data,
    bool showLoading = true,
    Map<String, dynamic>? headers,
  }) async {
    try {
      if (showLoading) TraxDialog.showLoading();
      final resp = await _dio.post(
        url,
        data: data,
        options: Options(headers: headers),
      );
      return AppResponse.fromJson(resp.data);
    } catch (e) {
      return AppResponse.error(e.toString());
    } finally {
      if (showLoading) TraxDialog.hideLoading();
    }
  }

  static Future<AppResponse> loginWithPasswd({
    required String username,
    required String password,
  }) async {
    return post(
      TraxUrl.loginWithPasswd,
      data: {'username': username, 'password': password},
      headers: {'Content-Type': _TraxContentType.json},
    );
  }

  static Future<AppResponse> sendCode({required String email}) async {
    return post(TraxUrl.sendCode, data: {'email': email});
  }

  static Future<AppResponse> verifyCode({required String email, required String code}) async {
    return post(TraxUrl.verifyCode, data: {'email': email, 'code': code});
  }

  static Future<AppResponse> registerByPwd({
    required String email,
    required String password,
    required String verificationCode,
  }) {
    return post(
      TraxUrl.registerByPwd,
      headers: {'Content-Type': _TraxContentType.json},
      data: {
        'username': email,
        'email': email,
        'password': password,
        'verificationCode': verificationCode,
      },
    );
  }

  /// 第三方登录的 url
  static String getWebLoginUrl(String path) {
    if (_isDebug) {
      // 如果是测试环境，则统一使用GitHub作为测试登录
      return '${TraxUrl.baseUrlDebugNoPort}${TraxUrl.loginWithGithub}';
    }
    return '${TraxUrl.baseUrlRelease}$path';
  }
}
