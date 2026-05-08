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

  @override
  void onInit() {
    emailController.text = TraxStorageUtil.getLoginEmail();
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
