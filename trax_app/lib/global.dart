import 'dart:ui';

class Global {
  Global._();

  static const String appName = 'TRAX';
  static const String fontFamily = 'HelveticaNeue';

  static const Color scaffoldBackgroundColor = Color(0xFFEDEDED);

  /// true: 请求测试地址
  static const bool testEnv = true;

  /// 打印日志
  static const bool showLog = true;

  /// 跳过登录验证，只展示UI
  static const bool skipRule = false;

  static const String skipRuleEmail = '123456789@qq.com';
  static const String skipRulePwd = '12345678';

  static const String privacyPolicyUrl = 'https://trax.com/privacy-policy';
  static const String termsOfServiceUrl = 'https://trax.com/terms-conditions';
}
