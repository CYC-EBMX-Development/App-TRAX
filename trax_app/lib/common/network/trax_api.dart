import 'package:dio/dio.dart';

import '../widgets/trax_dialog.dart';
import 'app_response.dart';
import 'app_token_interceptor.dart';

class TraxUrl {
  TraxUrl._();

  // 优先读取 --dart-define=API_BASE_URL=...，未提供时回落到生产地址。
  // release 包构建命令：
  //   flutter build apk --release --dart-define=API_BASE_URL=http://43.99.48.204/api
  static const String _apiBaseUrlOverride =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');
  static String get baseUrlRelease =>
      _apiBaseUrlOverride.isNotEmpty ? _apiBaseUrlOverride : 'http://43.99.48.204/api';
  static String get baseUrlDebug =>
      _apiBaseUrlOverride.isNotEmpty ? _apiBaseUrlOverride : 'http://43.99.48.204/api';

  static const String loginWithPasswd = '/auth/loginByPwd';
  static const String sendCode = '/auth/send-code';
  static const String verifyEmail = '/auth/verify-email';
  static const String registerByPwd = '/auth/registerByPwd';
  static const String resetPassword = '/auth/reset-password';
  static const String loginWithGoogle = '/sdk/googleLogin';
  static const String loginWithFacebook = '/sdk/facebookLogin';
  static const String loginWithApple = '/sdk/appleLogin';

  static const String traxModules = '/trax-modules';
  static const String bikeModels = '/bike-models';
  static const String brands = '/bike-models/brands';
  static const String bikes = '/bikes';
  static const String rides = '/rides';
  static const String modules = '/modules';
  static const String trails = '/trails';
  static const String races = '/races';
  static const String checkpoints = '/checkpoints';
  static const String users = '/users';
}

class _TraxContentType {
  static const Map<String, String> jsonHeaders = {'Content-Type': 'application/json'};
  static const Map<String, String> formHeaders = {'Content-Type': 'application/x-www-form-urlencoded'};
}

class TraxApi {
  TraxApi._();

  static late Dio _dio;
  static late bool _isDebug;

  static void init({required bool isDebug}) {
    _isDebug = isDebug;
    _dio = Dio(
      BaseOptions(
        baseUrl: _isDebug ? TraxUrl.baseUrlDebug : TraxUrl.baseUrlRelease,
        connectTimeout: const Duration(seconds: 25),
        receiveTimeout: const Duration(seconds: 25),
        headers: _TraxContentType.formHeaders,
        responseType: ResponseType.json,
      ),
    );
    _dio.interceptors.addAll([
      AppTokenInterceptor(),
    ]);
  }

  /// Build a human-friendly message from a [DioException]. Prefers a
  /// JSON `message` field from the backend body, then HTTP status, then
  /// the Dio exception type/native message. Avoids returning the useless
  /// "status: null, error: null" string seen in earlier builds.
  static String _formatDioError(DioException e) {
    final body = e.response?.data;
    if (body is Map && body['message'] is String && (body['message'] as String).isNotEmpty) {
      return body['message'] as String;
    }
    final status = e.response?.statusCode;
    if (status != null) {
      return 'HTTP $status: ${e.response?.statusMessage ?? e.message ?? "error"}';
    }
    String label;
    switch (e.type) {
      case DioExceptionType.connectionError:
        label = 'Network unavailable';
        break;
      case DioExceptionType.cancel:
        label = 'Request cancelled';
        break;
      case DioExceptionType.badCertificate:
        label = 'TLS error';
        break;
      case DioExceptionType.badResponse:
        label = 'Bad response';
        break;
      default:
        label = 'Network error';
    }
    final detail = e.message ?? e.error?.toString();
    return detail == null || detail.isEmpty ? label : '$label: $detail';
  }

  static Future<AppResponse> post(
    String url, {
    String path = '',
    required Object? data,
    bool showLoading = true,
    Map<String, dynamic>? headers,
  }) async {
    try {
      if (showLoading) TraxDialog.showLoading();
      try {
        final resp = await _dio.post('$url$path', data: data, options: Options(headers: headers));
        return AppResponse.fromJson(resp.data);
      } on DioException catch (e) {
        // One silent retry on connect/receive timeout (cold-start TLS handshake
        // can occasionally exceed the per-request budget).
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          final resp = await _dio.post('$url$path', data: data, options: Options(headers: headers));
          return AppResponse.fromJson(resp.data);
        }
        rethrow;
      }
    } catch (e) {
      if (e is DioException) {
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          return AppResponse.error('Request timeout!');
        }
        return AppResponse.error(_formatDioError(e));
      }
      return AppResponse.error(e.toString());
    } finally {
      if (showLoading) TraxDialog.hideLoading();
    }
  }

  static Future<AppResponse> get(
    String url, {
    String path = '',
    Map<String, dynamic>? queryParameters,
    bool showLoading = true,
    Map<String, dynamic>? headers,
  }) async {
    try {
      if (showLoading) TraxDialog.showLoading();
      try {
        final resp = await _dio.get('$url$path', queryParameters: queryParameters, options: Options(headers: headers));
        return AppResponse.fromJson(resp.data);
      } on DioException catch (e) {
        // One silent retry on connect/receive timeout (cold-start TLS handshake
        // can occasionally exceed the per-request budget).
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          final resp = await _dio.get('$url$path', queryParameters: queryParameters, options: Options(headers: headers));
          return AppResponse.fromJson(resp.data);
        }
        rethrow;
      }
    } catch (e) {
      if (e is DioException) {
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          return AppResponse.error('Request timeout!');
        }
        return AppResponse.error(_formatDioError(e));
      }
      return AppResponse.error(e.toString());
    } finally {
      if (showLoading) TraxDialog.hideLoading();
    }
  }

  // Auth endpoints
  static Future<AppResponse> loginWithPasswd({required String username, required String password}) {
    return post(TraxUrl.loginWithPasswd, data: {'username': username, 'password': password}, headers: _TraxContentType.jsonHeaders);
  }

  static Future<AppResponse> sendCode({required String email}) {
    return post(TraxUrl.sendCode, data: {'email': email});
  }

  static Future<AppResponse> verifyEmail({required String email}) {
    return get(TraxUrl.verifyEmail, queryParameters: {'email': email});
  }

  static Future<AppResponse> registerByPwd({required String email, required String password, required String verificationCode}) {
    return post(TraxUrl.registerByPwd, headers: _TraxContentType.jsonHeaders, data: {
      'username': email, 'email': email, 'password': password, 'verificationCode': verificationCode,
    });
  }

  static Future<AppResponse> resetPassword({required String email, required String password, required String verificationCode}) {
    return post(TraxUrl.resetPassword, headers: _TraxContentType.jsonHeaders, data: {
      'email': email, 'newPassword': password, 'verificationCode': verificationCode,
    });
  }

  /// Change the password for the currently authenticated user. The
  /// server verifies [oldPassword] against the stored bcrypt hash
  /// before applying [newPassword]. The user identity is taken from
  /// the bearer token attached by AppTokenInterceptor — no email
  /// needs to be passed in the body.
  static Future<AppResponse> changePassword({required String oldPassword, required String newPassword}) {
    return put(
      '${TraxUrl.users}/me/password',
      data: {'oldPassword': oldPassword, 'newPassword': newPassword},
      headers: _TraxContentType.jsonHeaders,
      showLoading: true,
    );
  }

  /// Step 1 of the in-app Change Password wizard: verify that the
  /// supplied [password] matches the current account's password. The
  /// server returns success without modifying anything; client uses the
  /// outcome to gate moving to step 2 (entering the new password).
  static Future<AppResponse> verifyPassword({required String password}) {
    return post(
      '${TraxUrl.users}/me/verify-password',
      data: {'oldPassword': password},
      headers: _TraxContentType.jsonHeaders,
    );
  }

  static Future<AppResponse> loginWithGoogle(String token) {
    final headers = {'Authorization': 'Bearer $token'};
    headers.addAll(_TraxContentType.jsonHeaders);
    return post(TraxUrl.loginWithGoogle, data: {}, headers: headers);
  }

  static Future<AppResponse> loginWithApple(String token) {
    final headers = {'Authorization': 'Bearer $token'};
    headers.addAll(_TraxContentType.jsonHeaders);
    return post(TraxUrl.loginWithApple, data: {}, headers: headers);
  }

  static Future<AppResponse> loginWithFacebook(String token) {
    final headers = {'Authorization': 'Bearer $token'};
    headers.addAll(_TraxContentType.jsonHeaders);
    return post(TraxUrl.loginWithFacebook, data: {}, headers: headers);
  }

  static Future<AppResponse> getTraxModules() =>
      get(TraxUrl.traxModules, showLoading: false);

  // ── User profile endpoints ────────────────────────────

  static Future<AppResponse> getCurrentUser() =>
      get(TraxUrl.users, path: '/me', showLoading: false);

  static Future<AppResponse> updateProfile({String? username, String? avatarUrl}) async {
    try {
      TraxDialog.showLoading();
      final resp = await _dio.put(
        '${TraxUrl.users}/me',
        data: {
          if (username != null) 'username': username,
          if (avatarUrl != null) 'avatarUrl': avatarUrl,
        },
        options: Options(headers: _TraxContentType.jsonHeaders),
      );
      return AppResponse.fromJson(resp.data);
    } catch (e) {
      if (e is DioException) {
        return AppResponse.error(_formatDioError(e));
      }
      return AppResponse.error(e.toString());
    } finally {
      TraxDialog.hideLoading();
    }
  }

  static Future<AppResponse> uploadAvatar(String filePath) async {
    try {
      TraxDialog.showLoading();
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath,
            filename: filePath.split('/').last),
      });
      final resp = await _dio.post(
        '${TraxUrl.users}/me/avatar',
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      return AppResponse.fromJson(resp.data);
    } catch (e) {
      if (e is DioException) {
        return AppResponse.error(_formatDioError(e));
      }
      return AppResponse.error(e.toString());
    } finally {
      TraxDialog.hideLoading();
    }
  }

  // Bike model endpoints
  static Future<AppResponse> getBrands() =>
      get(TraxUrl.brands, showLoading: false);

  static Future<AppResponse> getModelsByBrand(int brandId) =>
      get(TraxUrl.brands, path: '/$brandId/models', showLoading: false);

  // Bike CRUD endpoints
  static Future<AppResponse> getUserBikes() =>
      get(TraxUrl.bikes, showLoading: false);

  static Future<AppResponse> createBike(Map<String, dynamic> bikeData) =>
      post(TraxUrl.bikes, data: bikeData, headers: _TraxContentType.jsonHeaders);

  static Future<AppResponse> updateBike(String bikeId, Map<String, dynamic> bikeData) =>
      _dio.put('${TraxUrl.bikes}/$bikeId', data: bikeData, options: Options(headers: _TraxContentType.jsonHeaders))
          .then((resp) => AppResponse.fromJson(resp.data))
          .catchError((e) {
            if (e is DioException) {
              if (e.type == DioExceptionType.connectionTimeout ||
                  e.type == DioExceptionType.receiveTimeout) {
                return AppResponse.error('Request timeout!');
              }
              return AppResponse.error(_formatDioError(e));
            }
            return AppResponse.error(e.toString());
          });

  static Future<AppResponse> deleteBike(String bikeId) =>
      _dio.delete('${TraxUrl.bikes}/$bikeId')
          .then((resp) => AppResponse.fromJson(resp.data))
          .catchError((e) {
            if (e is DioException) {
              if (e.type == DioExceptionType.connectionTimeout ||
                  e.type == DioExceptionType.receiveTimeout) {
                return AppResponse.error('Request timeout!');
              }
              return AppResponse.error(_formatDioError(e));
            }
            return AppResponse.error(e.toString());
          });

  static Future<AppResponse> getBike(String bikeId) =>
      get(TraxUrl.bikes, path: '/$bikeId', showLoading: false);

  // ── PUT helper ──────────────────────────────────────────

  static Future<AppResponse> put(
    String url, {
    Object? data,
    bool showLoading = false,
    Map<String, dynamic>? headers,
  }) async {
    try {
      if (showLoading) TraxDialog.showLoading();
      final resp = await _dio.put(url, data: data, options: Options(headers: headers));
      return AppResponse.fromJson(resp.data);
    } catch (e) {
      if (e is DioException) {
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          return AppResponse.error('Request timeout!');
        }
        return AppResponse.error(_formatDioError(e));
      }
      return AppResponse.error(e.toString());
    } finally {
      if (showLoading) TraxDialog.hideLoading();
    }
  }

  // ── Ride endpoints ──────────────────────────────────────

  static Future<AppResponse> getUserRides() =>
      get(TraxUrl.rides, showLoading: false);

  static Future<AppResponse> getRideById(int rideId) =>
      get(TraxUrl.rides, path: '/$rideId', showLoading: false);

  static Future<AppResponse> getRidePoints(int rideId) =>
      get(TraxUrl.rides, path: '/$rideId/points', showLoading: false);

  static Future<AppResponse> getActiveRide() =>
      get(TraxUrl.rides, path: '/active', showLoading: false);

  static Future<AppResponse> startRide({required int bicycleId, required String mode, int? trailId, int? targetLaps}) =>
      post(TraxUrl.rides, path: '/start', data: {
        'bicycleId': bicycleId,
        'mode': mode,
        if (trailId != null) 'trailId': trailId,
        if (targetLaps != null) 'targetLaps': targetLaps,
      }, headers: _TraxContentType.jsonHeaders);

  static Future<AppResponse> pauseRide(int rideId) =>
      put('${TraxUrl.rides}/$rideId/pause');

  static Future<AppResponse> resumeRide(int rideId) =>
      put('${TraxUrl.rides}/$rideId/resume');

  static Future<AppResponse> stopRide(int rideId) =>
      put('${TraxUrl.rides}/$rideId/stop', showLoading: true);

  static Future<AppResponse> addRidePoints(int rideId, List<Map<String, dynamic>> points) =>
      post(TraxUrl.rides, path: '/$rideId/points', data: {'points': points},
          headers: _TraxContentType.jsonHeaders, showLoading: false);

  static Future<AppResponse> getRideStats(int rideId) =>
      get(TraxUrl.rides, path: '/$rideId/stats', showLoading: false);

  static Future<AppResponse> getRideLaps(int rideId) =>
      get(TraxUrl.rides, path: '/$rideId/laps', showLoading: false);

  static Future<AppResponse> deleteRide(int rideId) =>
      _dio.delete('${TraxUrl.rides}/$rideId')
          .then((resp) => AppResponse.fromJson(resp.data))
          .catchError((e) {
            if (e is DioException) {
              if (e.type == DioExceptionType.connectionTimeout ||
                  e.type == DioExceptionType.receiveTimeout) {
                return AppResponse.error('Request timeout!');
              }
              return AppResponse.error(_formatDioError(e));
            }
            return AppResponse.error(e.toString());
          });

  // ── Mock endpoints ─────────────────────────────────────

  /// Fetch a closed-loop road-following route around (lat, lng) for "Simulate Lap".
  static Future<AppResponse> getMockLapRoute(double lat, double lng) =>
      get('/mock/lap-route',
          queryParameters: {'lat': lat, 'lng': lng}, showLoading: false);

  // ── Trail endpoints ────────────────────────────────────

  static Future<AppResponse> getTrails() =>
      get(TraxUrl.trails, showLoading: false);

  static Future<AppResponse> createTrail(Map<String, dynamic> data) =>
      post(TraxUrl.trails, path: '/create', data: data,
          headers: _TraxContentType.jsonHeaders);

  static Future<AppResponse> getTrailPoints(int trailId) =>
      get(TraxUrl.trails, path: '/$trailId/points', showLoading: false);

  static Future<AppResponse> deleteTrail(int trailId) =>
      _dio.delete('${TraxUrl.trails}/$trailId')
          .then((resp) => AppResponse.fromJson(resp.data))
          .catchError((e) {
            if (e is DioException) {
              if (e.type == DioExceptionType.connectionTimeout ||
                  e.type == DioExceptionType.receiveTimeout) {
                return AppResponse.error('Request timeout!');
              }
              return AppResponse.error(_formatDioError(e));
            }
            return AppResponse.error(e.toString());
          });

  static Future<AppResponse> getTrailCheckpoints(int trailId) =>
      get(TraxUrl.checkpoints, path: '/trail/$trailId', showLoading: false);

  static Future<AppResponse> addTrailCheckpoint(
          int trailId, double latitude, double longitude) =>
      post(TraxUrl.checkpoints, path: '/trail/$trailId',
          data: {'latitude': latitude, 'longitude': longitude},
          headers: _TraxContentType.jsonHeaders);

  static Future<AppResponse> deleteTrailCheckpoint(int checkpointId) =>
      _dio.delete('${TraxUrl.checkpoints}/$checkpointId')
          .then((resp) => AppResponse.fromJson(resp.data))
          .catchError((e) {
            if (e is DioException) {
              return AppResponse.error(
                  'status: ${e.response?.statusCode}, error: ${e.response?.statusMessage}');
            }
            return AppResponse.error(e.toString());
          });

  static Future<AppResponse> updateTrailVisibility(int trailId, bool isPublic) =>
      _dio.patch('${TraxUrl.trails}/$trailId/visibility',
          data: {'isPublic': isPublic},
          options: Options(contentType: 'application/json'))
          .then((resp) => AppResponse.fromJson(resp.data))
          .catchError((e) {
            if (e is DioException) {
              return AppResponse.error(_formatDioError(e));
            }
            return AppResponse.error(e.toString());
          });

  // ── Module telemetry endpoints ──────────────────────────

  static Future<AppResponse> getModuleTelemetry(String serialNo) =>
      get(TraxUrl.modules, path: '/$serialNo/telemetry/latest', showLoading: false);

  static Future<AppResponse> startSimulation(String serialNo, {double? latitude, double? longitude, int? rideId}) {
    final params = 'serialNo=$serialNo';
    final latParam = latitude != null ? '&latitude=$latitude' : '';
    final lngParam = longitude != null ? '&longitude=$longitude' : '';
    final rideParam = rideId != null ? '&rideId=$rideId' : '';
    return post(TraxUrl.modules, path: '/simulate/start?$params$latParam$lngParam$rideParam',
        data: {}, showLoading: false);
  }

  static Future<AppResponse> pauseSimulation(String serialNo) =>
      post(TraxUrl.modules, path: '/simulate/pause?serialNo=$serialNo',
          data: {}, showLoading: false);

  static Future<AppResponse> resumeSimulation(String serialNo) =>
      post(TraxUrl.modules, path: '/simulate/resume?serialNo=$serialNo',
          data: {}, showLoading: false);

  static Future<AppResponse> stopSimulation(String serialNo) =>
      post(TraxUrl.modules, path: '/simulate/stop?serialNo=$serialNo',
          data: {}, showLoading: false);

  // ── Race endpoints ─────────────────────────────────────

  static Future<AppResponse> createRace(Map<String, dynamic> data) =>
      post(TraxUrl.races, data: data, headers: _TraxContentType.jsonHeaders);

  static Future<AppResponse> getRace(int raceId) =>
      get(TraxUrl.races, path: '/$raceId', showLoading: false);

  static Future<AppResponse> joinRace(int raceId, {int? bicycleId}) =>
      post(TraxUrl.races, path: '/$raceId/join',
          data: bicycleId != null ? {'bicycleId': bicycleId} : {},
          headers: _TraxContentType.jsonHeaders, showLoading: false);

  static Future<AppResponse> joinByCode(String code, {String role = 'rider', int? bicycleId}) =>
      post(TraxUrl.races, path: '/join-by-code',
          data: {'joinCode': code, 'role': role, if (bicycleId != null) 'bicycleId': bicycleId},
          headers: _TraxContentType.jsonHeaders);

  static Future<AppResponse> observeRace(int raceId) =>
      post(TraxUrl.races, path: '/$raceId/observe',
          data: {}, headers: _TraxContentType.jsonHeaders, showLoading: false);

  static Future<AppResponse> quitRace(int raceId) =>
      post(TraxUrl.races, path: '/$raceId/quit',
          data: {}, headers: _TraxContentType.jsonHeaders, showLoading: false);

  static Future<AppResponse> updateRaceType(int raceId, bool isPublic) =>
      post(TraxUrl.races, path: '/$raceId/type',
          data: {'isPublic': isPublic}, headers: _TraxContentType.jsonHeaders);

  static Future<AppResponse> updateRaceSettings(
    int raceId, {
    int? trailId,
    int? targetLaps,
    int? maxParticipants,
    Object? scheduledTime, // String ISO, '' to clear, or null to leave unchanged
  }) {
    final data = <String, dynamic>{};
    if (trailId != null) data['trailId'] = trailId;
    if (targetLaps != null) data['targetLaps'] = targetLaps;
    if (maxParticipants != null) data['maxParticipants'] = maxParticipants;
    if (scheduledTime != null) data['scheduledTime'] = scheduledTime;
    return post(TraxUrl.races,
        path: '/$raceId/settings',
        data: data,
        headers: _TraxContentType.jsonHeaders);
  }

  static Future<AppResponse> startRaceEvent(int raceId) =>
      post(TraxUrl.races, path: '/$raceId/start',
          data: {}, headers: _TraxContentType.jsonHeaders);

  static Future<AppResponse> readyForRace(int raceId) =>
      post(TraxUrl.races, path: '/$raceId/ready',
          data: {}, headers: _TraxContentType.jsonHeaders, showLoading: false);

  static Future<AppResponse> setRaceBike(int raceId, {int? bicycleId}) =>
      post(TraxUrl.races, path: '/$raceId/set-bike',
          data: {'bicycleId': bicycleId},
          headers: _TraxContentType.jsonHeaders, showLoading: false);

  static Future<AppResponse> reportLocation(
          int raceId, double latitude, double longitude) =>
      post(TraxUrl.races,
          path: '/$raceId/location',
          data: {'latitude': latitude, 'longitude': longitude},
          headers: _TraxContentType.jsonHeaders, showLoading: false);

  static Future<AppResponse> goRace(int raceId) =>
      post(TraxUrl.races, path: '/$raceId/go',
          data: {}, headers: _TraxContentType.jsonHeaders, showLoading: false);

  static Future<AppResponse> stopRaceEvent(int raceId) =>
      post(TraxUrl.races, path: '/$raceId/stop',
          data: {}, headers: _TraxContentType.jsonHeaders, showLoading: false);

  static Future<AppResponse> cancelRaceEvent(int raceId) =>
      post(TraxUrl.races, path: '/$raceId/cancel',
          data: {}, headers: _TraxContentType.jsonHeaders, showLoading: false);

  static Future<AppResponse> getRaceLive(int raceId) =>
      get(TraxUrl.races, path: '/$raceId/live', showLoading: false);

  static Future<AppResponse> getPublicRaces() =>
      get(TraxUrl.races, path: '/public', showLoading: false);

  static Future<AppResponse> getPublicRacesForObserver() =>
      get(TraxUrl.races, path: '/public/observe', showLoading: false);

  static Future<AppResponse> getUpcomingEvents() =>
      get(TraxUrl.races, path: '/upcoming', showLoading: false);

  static Future<AppResponse> getMyEvents({int page = 0, int size = 20}) =>
      get(TraxUrl.races, path: '/my-events',
          queryParameters: {'page': page, 'size': size}, showLoading: false);
}

