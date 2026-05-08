import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common/network/trax_api.dart';
import '../../common/utils/trax_validator_util.dart';
import '../../common/widgets/trax_button.dart';
import '../../common/widgets/trax_dialog.dart';
import '../../common/widgets/trax_page_widget.dart';
import '../../common/widgets/trax_text_field.dart';
import '../../global.dart';
import '../../routers/trax_router.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class ResetPwdPageBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(ResetPwdController());
  }
}

class ResetPwdController extends GetxController {
  final TextEditingController newPwdController = TextEditingController();
  final TextEditingController confirmPwdController = TextEditingController();

  final formKey = GlobalKey<FormState>();

  late final String email;
  late final String verificationCode;

  @override
  void onInit() {
    email = Get.parameters['email'] ?? '';
    verificationCode = Get.parameters['verificationCode'] ?? '';
    if (Global.skipRule) {
      newPwdController.text = Global.skipRulePwd;
      confirmPwdController.text = Global.skipRulePwd;
    }
    super.onInit();
  }

  void resetPwd() async {
    if (!formKey.currentState!.validate()) {
      return;
    }
    if (newPwdController.text != confirmPwdController.text) {
      TraxDialog.messageTopDialog('Passwords do not match', false);
      return;
    }

    if (Global.skipRule) {
      await TraxRouter.toResetPwdSuccessPage();
      return;
    }

    final response = await TraxApi.resetPassword(
      email: email,
      password: newPwdController.text,
      verificationCode: verificationCode,
    );
    if (!response.isSuccess()) {
      TraxDialog.messageTopDialog(response.message, response.flag);
      return;
    }
    await TraxRouter.toResetPwdSuccessPage();
  }
}

class ResetPwdPage extends GetView<ResetPwdController> {
  const ResetPwdPage({super.key});

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '706', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      appBar: TraxAppBar(),
      extendBodyBehindAppBar: true,
      body: TraxPageBody(
        showBackground: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Reset Password', style: TextStyle(fontSize: 35, fontWeight: FontWeight.bold)),
            const SizedBox(height: 60),
            Form(
              key: controller.formKey,
              child: Column(
                children: [
                  TraxTextField(
                    hintText: 'New Password',
                    inPutPassword: true,
                    validator: TraxValidatorUtil.validatePassword,
                    controller: controller.newPwdController,
                  ),
                  const SizedBox(height: 20),
                  TraxTextField(
                    hintText: 'Confirm Password',
                    inPutPassword: true,
                    validator: TraxValidatorUtil.validatePassword,
                    controller: controller.confirmPwdController,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            TraxButton.filled(
              text: 'Confirm',
              backgroundColor: Colors.white,
              textStyle: const TextStyle(color: Colors.black, fontSize: 24.0, fontWeight: FontWeight.w700),
              expand: true,
              onPressed: () => controller.resetPwd(),
            ),
          ],
        ),
      ),
    );
  }
}
