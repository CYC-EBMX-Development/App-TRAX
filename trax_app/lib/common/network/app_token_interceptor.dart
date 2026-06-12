import 'dart:async';

import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;

import '../../routers/trax_router.dart';
import '../../services/active_ride_service.dart';
import '../models/user_model.dart';
import '../utils/trax_storage_util.dart';
import 'app_response.dart';
import 'trax_api.dart';

class AppTokenInterceptor extends Interceptor {
  AppTokenInterceptor(this._dio);

  /// The shared Dio instance owned by [TraxApi]. Used to replay the
  /// original request after a successful silent token refresh.
  final Dio _dio;

  // Coalesces simultaneous 401/403 storms (e.g. multiple ride-related
  // pollers all firing within a few hundred ms after the token expires)
  // so we don't navigate / clearToken N times. Re-armed shortly after
  // the navigation completes so genuinely new auth failures still fire.
  static bool _handlingExpired = false;
  static const Duration _reArmDelay = Duration(seconds: 2);

  // Single-flight gate for the refresh-token exchange. The first 401 in
  // a storm kicks off `POST /api/auth/refresh`; every concurrent 401
  // awaits the same future so we never fire N refreshes in parallel
  // (which would rotate the refresh token N times and invalidate N-1
  // requests). Reset to `null` after completion so the next genuine
  // expiry can trigger a new refresh.
  static Completer<bool>? _refreshInFlight;

  /// Per-request marker set on the [RequestOptions.extra] map after a
  /// silent refresh + retry, so a second 401 on the replay can't loop
  /// back into another refresh attempt.
  static const String _retriedKey = '_trax_retried_after_refresh';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    String token = TraxStorageUtil.getToken();
    if (token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    super.onRequest(options, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    if (status == 401 || status == 403) {
      // Already replayed once \u2014 stop trying, log the user out.
      if (err.requestOptions.extra[_retriedKey] == true) {
        _handleTokenExpired();
        handler.reject(err);
        return;
      }

      // Try silent refresh + replay before declaring the session dead.
      final refreshed = await _attemptRefresh();
      if (refreshed) {
        try {
          final retryOpts = err.requestOptions
            ..extra[_retriedKey] = true
            ..headers['Authorization'] = 'Bearer ${TraxStorageUtil.getToken()}';
          final replay = await _dio.fetch(retryOpts);
          handler.resolve(replay);
          return;
        } catch (e) {
          if (e is DioException) {
            handler.reject(e);
          } else {
            handler.reject(err);
          }
          return;
        }
      }

      // Refresh failed (no refresh token, expired refresh token, or
      // network error) \u2014 fall back to the original logout flow.
      _handleTokenExpired();
      handler.reject(err);
      return;
    }
    super.onError(err, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    // 检测响应中的token过期错误 (200 OK envelope carrying code:401)
    if (response.statusCode == 200 && response.data is Map) {
      final data = response.data as Map<String, dynamic>;
      final isExpired = data['code'] == 401 &&
          data['message']?.toString().contains('token') == true;
      if (isExpired) {
        if (response.requestOptions.extra[_retriedKey] != true) {
          final refreshed = await _attemptRefresh();
          if (refreshed) {
            try {
              final retryOpts = response.requestOptions
                ..extra[_retriedKey] = true
                ..headers['Authorization'] = 'Bearer ${TraxStorageUtil.getToken()}';
              final replay = await _dio.fetch(retryOpts);
              handler.resolve(replay);
              return;
            } catch (_) {
              // fall through to logout
            }
          }
        }
        _handleTokenExpired();
        handler.resolve(response);
        return;
      }
    }
    super.onResponse(response, handler);
  }

  /// Single-flight silent refresh. Returns `true` when the stored tokens
  /// were rotated successfully and the caller can replay the request.
  Future<bool> _attemptRefresh() async {
    // If a refresh is already running, await its outcome instead of
    // firing a second concurrent /auth/refresh.
    final existing = _refreshInFlight;
    if (existing != null) {
      return existing.future;
    }
    final completer = Completer<bool>();
    _refreshInFlight = completer;
    try {
      final rt = TraxStorageUtil.getRefreshToken();
      if (rt.isEmpty) {
        completer.complete(false);
        return false;
      }
      final AppResponse resp = await TraxApi.refreshToken(refreshToken: rt);
      if (!resp.flag || resp.data is! Map) {
        completer.complete(false);
        return false;
      }
      final lm = LoginModel.fromJson(
        (resp.data as Map).cast<String, dynamic>(),
      );
      final newAccess = lm.accessToken ?? '';
      final newRefresh = lm.refreshToken ?? '';
      if (newAccess.isEmpty || newRefresh.isEmpty) {
        completer.complete(false);
        return false;
      }
      await TraxStorageUtil.saveToken(newAccess);
      await TraxStorageUtil.saveRefreshToken(newRefresh);
      if (lm.tokenType != null && lm.tokenType!.isNotEmpty) {
        await TraxStorageUtil.saveTokenType(lm.tokenType);
      }
      completer.complete(true);
      return true;
    } catch (_) {
      if (!completer.isCompleted) completer.complete(false);
      return false;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<void> _handleTokenExpired() async {
    if (_handlingExpired) return;
    _handlingExpired = true;
    try {
      // 1. Stop the abandoned-ride background traffic (3s stats poll,
      //    5s point upload, telemetry poll, lap WS, module WS). Without
      //    this, those timers keep hitting the API with a now-stale
      //    rideId, each 401 calls _handleTokenExpired() again, which
      //    re-fires Get.offAllNamed('/welcome') and yanks the user off
      //    whatever auth screen they tried to open. This was the root
      //    cause of the "login page bounces back on every tap" loop
      //    reported 2026-06-05.
      ActiveRideService.instance.forceResetForLogout();

      // 2. Wipe token + login_time so WelcomeMiddleware.isLogin() goes
      //    false and won't redirect /welcome → /main.
      await TraxStorageUtil.clearToken();

      // 3. Navigate to welcome ONLY when the user isn't already on an
      //    auth screen. If they tapped Login → /login, a stray late
      //    401 would otherwise offAllNamed back to /welcome and erase
      //    whatever they were typing.
      final current = Get.currentRoute;
      if (!TraxRouter.isAuthRoute(current)) {
        Get.offAllNamed(TraxRouter.welcomePage);
      }
    } finally {
      Future.delayed(_reArmDelay, () => _handlingExpired = false);
    }
  }
}
