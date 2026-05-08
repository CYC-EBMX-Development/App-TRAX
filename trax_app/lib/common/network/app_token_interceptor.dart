import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import '../utils/trax_storage_util.dart';

class AppTokenInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    String token = TraxStorageUtil.getToken();
    if (token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    super.onRequest(options, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // 检测token过期（401 Unauthorized 或 403 Forbidden）
    if (err.response?.statusCode == 401 || err.response?.statusCode == 403) {
      _handleTokenExpired();
      return;
    }
    super.onError(err, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // 检测响应中的token过期错误
    if (response.statusCode == 200 && response.data is Map) {
      final data = response.data as Map<String, dynamic>;
      if (data['code'] == 401 && data['message']?.toString().contains('token') == true) {
        _handleTokenExpired();
        return;
      }
    }
    super.onResponse(response, handler);
  }

  void _handleTokenExpired() {
    // 清除token
    TraxStorageUtil.clearToken();

    // 跳转到登录页面
    Get.offAllNamed('/welcome');
  }
}
