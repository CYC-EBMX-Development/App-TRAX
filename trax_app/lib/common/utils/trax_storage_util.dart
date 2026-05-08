import 'package:shared_preferences/shared_preferences.dart';

class TraxStorageUtil {
  static const String _keyToken = "trax_token";
  static const String _keyTokenType = "trax_token_type";
  static const String _keyUserInfo = "trax_user_info";
  static const String _keyLoginEmail = "trax_login_email";
  static const String _keyLoginTime = "trax_login_time";
  static const String _keySelectedBikeId = "trax_selected_bike_id";
  static const int _loginExpireDays = 30;

  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static Future<void> _setString(String key, String value) async {
    await _prefs.setString(key, value);
  }

  static String _getString(String key) {
    try {
      return _prefs.getString(key) ?? '';
    } catch (e) {
      return '';
    }
  }

  static Future<void> saveLoginEmail(String? email) async {
    await _setString(_keyLoginEmail, email ?? '');
  }

  static String getLoginEmail() => _getString(_keyLoginEmail);

  static Future<void> saveToken(String? token) async {
    await _setString(_keyToken, token ?? '');
    if (token != null && token.isNotEmpty) {
      await _prefs.setInt(_keyLoginTime, DateTime.now().millisecondsSinceEpoch);
    }
  }

  static String getToken() => _getString(_keyToken);

  static Future<void> saveTokenType(String? tokenType) async {
    await _setString(_keyTokenType, tokenType ?? '');
  }

  static String getTokenType() => _getString(_keyTokenType);

  static bool isLogin() {
    final token = getToken();
    if (token.isEmpty) return false;
    final loginTime = _prefs.getInt(_keyLoginTime) ?? 0;
    if (loginTime == 0) return false;
    final expiry = DateTime.fromMillisecondsSinceEpoch(loginTime)
        .add(const Duration(days: _loginExpireDays));
    if (DateTime.now().isAfter(expiry)) {
      clearWithoutEmail(); // fire-and-forget: clear expired session
      return false;
    }
    return true;
  }

  static Future<void> saveUserInfo(String? userInfo) async {
    await _setString(_keyUserInfo, userInfo ?? '');
  }

  static String getUserInfo() => _getString(_keyUserInfo);

  static Future<bool> clearWithoutEmail() async {
    String email = getLoginEmail();
    if (!await _prefs.clear()) return false;
    await saveLoginEmail(email);
    return true;
  }

  static Future<void> clearToken() async {
    await _setString(_keyToken, '');
    await _setString(_keyTokenType, '');
    await _prefs.remove(_keyLoginTime);
  }

  static Future<bool> clearAll() async {
    return await _prefs.clear();
  }

  static Future<void> saveSelectedBikeId(String bikeId) async {
    await _setString(_keySelectedBikeId, bikeId);
  }

  static String getSelectedBikeId() => _getString(_keySelectedBikeId);
}
