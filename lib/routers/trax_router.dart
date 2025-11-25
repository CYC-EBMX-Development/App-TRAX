import 'package:get/get.dart';
import 'package:tra_x/common/utils/trax_log_util.dart';
import 'package:tra_x/common/utils/trax_navigation_util.dart';
import 'package:tra_x/features/login/create_account_page.dart';
import 'package:tra_x/features/login/create_pwd_page.dart';
import 'package:tra_x/features/login/forgot_pwd_page.dart';
import 'package:tra_x/features/login/login_page.dart';
import 'package:tra_x/features/login/login_page_controller.dart';
import 'package:tra_x/features/login/reset_pwd_page.dart';
import 'package:tra_x/features/login/verification_page.dart';
import 'package:tra_x/features/login/web_view_page.dart';
import 'package:tra_x/features/login/welcome_page.dart';

class TraxRouter {
  TraxRouter._();

  /// 路由回调
  static void routingCallback(Routing? routing) {
    TraxLogUtil.debug("当前路由：${routing?.current}");
  }

  static final List<GetPage<dynamic>> pages = [
    GetPage(name: welcomePage, page: () => const WelcomePage()),
    GetPage(name: _loginPage, page: () => const LoginPage(), binding: LoginPageBinding()),
    GetPage(
      name: _forgotPwdPage,
      page: () => const ForgotPwdPage(),
      binding: ForgotPwdPageBinding(),
    ),
    GetPage(
      name: _createAccountPage,
      page: () => const CreateAccountPage(),
      binding: CreateAccountPageBinding(),
    ),
    GetPage(
      name: _createPwdPage,
      page: () => const CreatePwdPage(),
      binding: CreatePwdPageBinding(),
    ),
    GetPage(
      name: _verificationPage,
      page: () => VerificationPage(),
      // binding: CreatePwdPageBinding(),
    ),
    GetPage(name: _resetPwdPage, page: () => const ResetPwdPage(), binding: ResetPwdPageBinding()),
    GetPage(name: _webViewPage, page: () => const WebViewPage(), binding: WebViewPageBinding()),
  ];

  // 以后再改
  static const String welcomePage = '/welcome';

  static const String _loginPage = '/login';

  static Future<void> toLoginPage() async => TraxNaviUtil.pushNamed(_loginPage);

  static Future<void> toLoginPageOffAll() async => TraxNaviUtil.pushAndRemoveAll(_loginPage);

  // forgot password page
  static const String _forgotPwdPage = '/forgot_password';

  static Future<void> toForgotPwdPage() async => TraxNaviUtil.pushNamed(_forgotPwdPage);

  // create account page
  static const String _createAccountPage = '/create_account';

  static Future<void> toCreateAccountPage() async => TraxNaviUtil.pushNamed(_createAccountPage);

  // create pwd page
  static const String _createPwdPage = '/create_pwd';

  static Future<void> toCreatePwdPage(String email, String verifyCode) async =>
      TraxNaviUtil.pushNamed(
        _createPwdPage,
        parameters: {'email': email, 'verificationCode': verifyCode},
      );

  // verification page
  static const String _verificationPage = '/verification';

  /// to verification page
  ///
  /// return true if verification success
  static Future<bool> toVerificationPage(String email, void Function(String code) onSuccess) async {
    final result = await TraxNaviUtil.pushNamed(
      _verificationPage,
      arg: onSuccess,
      parameters: {'email': email},
    );
    return result == true;
  }

  // reset password page
  static const String _resetPwdPage = '/reset_pwd';

  // to reset password page
  static Future<void> toResetPwdPage() async => TraxNaviUtil.pushNamed(_resetPwdPage);

  // webView page
  static const String _webViewPage = '/web_view';

  static Future<void> toWebViewPage(String title, String url) async =>
      TraxNaviUtil.pushNamed(_webViewPage, parameters: {'title': title, 'url': url});
}
