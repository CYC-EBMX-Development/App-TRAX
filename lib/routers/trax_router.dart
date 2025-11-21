import 'package:get/get.dart';
import 'package:tra_x/common/utils/trax_log_util.dart';
import 'package:tra_x/features/login/forgot_password_page.dart';
import 'package:tra_x/features/login/login_page.dart';
import 'package:tra_x/features/login/login_page_controller.dart';
import 'package:tra_x/features/login/sign_up_page.dart';
import 'package:tra_x/features/login/welcome_page.dart';

class TraxRouter {
  TraxRouter._();

  /// 路由回调
  static void routingCallback(Routing? routing) {
    TraxLogUtil.debug("当前路由：${routing?.current}");
  }

  static final List<GetPage<dynamic>> pages = [
    GetPage(name: welcomePage, page: () => const WelcomePage()),
    GetPage(name: loginPage, page: () => const LoginPage(), binding: LoginPageBinding()),
    GetPage(
      name: forgotPwdPage,
      page: () => const ForgotPasswordPage(),
      binding: ForgotPasswordPageBinding(),
    ),
    GetPage(
      name: signUpPage,
      page: () => const SignUpPage(),
      binding: SignUpPageBinding(),
    ),
  ];

  static const String welcomePage = '/welcome';
  static const String loginPage = '/login';

  // forgot password page
  static const String forgotPwdPage = '/forgot_password';

  // sign up page
  static const String signUpPage = '/sign_up';
}
