import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common/global/global_user_info.dart';
import '../../common/models/user_model.dart';
import '../../common/network/app_response.dart';
import '../../common/network/trax_api.dart';
import '../../common/utils/trax_storage_util.dart';
import '../../common/widgets/trax_dialog.dart';
import '../../global.dart';
import '../../routers/trax_router.dart';

class LoginPageBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(LoginPageController());
  }
}

class LoginPageController extends GetxController {
  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();

  final formKey = GlobalKey<FormState>();

  // Optional dev-time default email injected at build time via
  //   --dart-define=DEV_DEFAULT_EMAIL=joshuawang@cycmotor.com
  // Only used when no email has been remembered yet (first install through
  // the maintainer's own build scripts). Production builds for end-users
  // simply omit the dart-define and behaviour is unchanged.
  static const String _devDefaultEmail =
      String.fromEnvironment('DEV_DEFAULT_EMAIL');

  @override
  void onInit() {
    // Priority: previously-saved login email > build-time dev default > empty.
    final saved = TraxStorageUtil.getLoginEmail();
    if (saved.isNotEmpty) {
      emailController.text = saved;
    } else if (_devDefaultEmail.isNotEmpty) {
      emailController.text = _devDefaultEmail;
    }
    if (Global.skipRule) {
      emailController.text = Global.skipRuleEmail;
      passwordController.text = Global.skipRulePwd;
    }
    super.onInit();
  }

  void login() async {
    if (!formKey.currentState!.validate()) {
      return;
    }
    if (Global.skipRule) {
      TraxRouter.toMainPageOffAll();
      return;
    }
    AppResponse response = await TraxApi.loginWithPasswd(
      username: emailController.text,
      password: passwordController.text,
    );
    TraxDialog.messageTopDialog(response.message, response.flag);
    if (response.flag) {
      final loginModel = LoginModel.fromJson(response.data);
      loginSuccess(loginModel);
    }
  }

  void toForgotPwdPage() async {
    await TraxRouter.toForgotPwdPage();
  }

  void toCreateAccountPage() async {
    await TraxRouter.toCreateAccountPage();
  }

  Future<void> loginSuccess(LoginModel loginModel) async {
    TraxStorageUtil.saveToken(loginModel.accessToken);
    TraxStorageUtil.saveRefreshToken(loginModel.refreshToken);
    TraxStorageUtil.saveTokenType(loginModel.tokenType);
    TraxStorageUtil.saveUserInfo(loginModel.user?.toJson());
    TraxStorageUtil.saveLoginEmail(loginModel.user?.email);
    GlobalUserInfo.instance.setUserInfo(
      id: loginModel.user?.id,
      name: loginModel.user?.username,
      email: loginModel.user?.email,
      avatar: loginModel.user?.avatarUrl,
    );
    TraxRouter.toMainPageOffAll();
  }
}
