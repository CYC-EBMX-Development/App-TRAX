import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../common/utils/trax_navigation_util.dart';
import '../common/utils/trax_storage_util.dart';
import '../features/login/create_account_page.dart';
import '../features/login/create_pwd_page.dart';
import '../features/login/forgot_pwd_page.dart';
import '../features/login/login_page.dart';
import '../features/login/login_page_controller.dart';
import '../features/login/reset_pwd_page.dart';
import '../features/login/reset_pwd_success_page.dart';
import '../features/login/verification_page.dart';
import '../features/login/welcome_page.dart';
import '../screens/main/main_screen.dart';

class TraxRouter {
  TraxRouter._();

  static final List<GetPage<dynamic>> pages = [
    GetPage(name: welcomePage, page: () => const WelcomePage(), middlewares: [WelcomeMiddleware()]),
    GetPage(name: _loginPage, page: () => const LoginPage(), binding: LoginPageBinding()),
    GetPage(name: _forgotPwdPage, page: () => const ForgotPwdPage(), binding: ForgotPwdPageBinding()),
    GetPage(name: _createAccountPage, page: () => const CreateAccountPage(), binding: CreateAccountPageBinding()),
    GetPage(name: _createPwdPage, page: () => const CreatePwdPage(), binding: CreatePwdPageBinding()),
    GetPage(name: _verificationPage, page: () => const VerificationPage(), binding: VerificationPageBinding()),
    GetPage(name: _resetPwdPage, page: () => const ResetPwdPage(), binding: ResetPwdPageBinding()),
    GetPage(name: _resetPwdSuccessPage, page: () => const ResetPwdSuccessPage(), binding: ResetPwdSuccessPageBinding()),
    GetPage(name: mainPage, page: () => const MainScreen()),
  ];

  // Route names
  static const String welcomePage = '/welcome';
  static const String _loginPage = '/login';
  static const String _forgotPwdPage = '/forgot_password';
  static const String _createAccountPage = '/create_account';
  static const String _createPwdPage = '/create_pwd';
  static const String _verificationPage = '/verification';
  static const String _resetPwdPage = '/reset_pwd';
  static const String _resetPwdSuccessPage = '/reset_pwd_success';
  static const String mainPage = '/main';

  // Navigation methods
  static Future<void> toWelcomePageOffAll() async => TraxNaviUtil.pushAndRemoveAll(welcomePage);

  static Future<void> toLoginPage() async => TraxNaviUtil.pushNamed(_loginPage);

  static Future<void> toLoginPageOffAll() async => TraxNaviUtil.pushAndRemoveAll(_loginPage);

  static Future<void> toForgotPwdPage() async => TraxNaviUtil.pushNamed(_forgotPwdPage);

  static Future<void> toCreateAccountPage() async => TraxNaviUtil.pushNamed(_createAccountPage);

  static Future<void> toCreatePwdPage(String email, Function(String pwd) onSuccess) async =>
      TraxNaviUtil.pushNamed(_createPwdPage, parameters: {'email': email}, arg: onSuccess);

  static Future<void> toVerificationPage(String email, void Function(String code) onSuccess) async {
    await TraxNaviUtil.pushNamed(
      _verificationPage,
      arg: onSuccess,
      parameters: {'email': email},
    );
  }

  static Future<void> toResetPwdPage(String email, String verificationCode) async =>
      TraxNaviUtil.pushNamed(
        _resetPwdPage,
        parameters: {'email': email, 'verificationCode': verificationCode},
      );

  static Future<void> toResetPwdSuccessPage() async => TraxNaviUtil.pushNamed(_resetPwdSuccessPage);

  static Future<void> toMainPageOffAll() async => TraxNaviUtil.pushAndRemoveAll(mainPage);

  /// Routes that do NOT require a valid auth token. Used by
  /// [AppTokenInterceptor] to avoid yanking the user off the login /
  /// sign-up form when background 401s keep firing during the
  /// post-logout settling window.
  static const Set<String> _authRoutes = {
    welcomePage,
    _loginPage,
    _forgotPwdPage,
    _createAccountPage,
    _createPwdPage,
    _verificationPage,
    _resetPwdPage,
    _resetPwdSuccessPage,
  };

  static bool isAuthRoute(String? routeName) =>
      routeName != null && _authRoutes.contains(routeName);
}

class WelcomeMiddleware extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    if (!TraxStorageUtil.isLogin()) {
      return null;
    }
    return const RouteSettings(name: TraxRouter.mainPage);
  }
}
