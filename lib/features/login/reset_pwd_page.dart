import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_x/common/network/trax_api.dart';
import 'package:tra_x/common/utils/trax_validator_util.dart';
import 'package:tra_x/common/widgets/trax_button.dart';
import 'package:tra_x/common/widgets/trax_dialog.dart';
import 'package:tra_x/common/widgets/trax_text.dart';
import 'package:tra_x/common/widgets/trax_text_field.dart';
import 'package:tra_x/routers/trax_router.dart';

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
    final response = await TraxApi.resetPassword(
      email: email,
      password: newPwdController.text,
      verificationCode: verificationCode,
    );
    if (!response.flag) {
      TraxDialog.messageTopDialog(response.message, response.flag);
      return;
    }
    await TraxRouter.toResetPwdSuccessPage();
  }
}

class ResetPwdPage extends GetView<ResetPwdController> {
  const ResetPwdPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TraxReturnButton(),
              const SizedBox(height: 40),
              const TraxText(
                'Reset Password',
                style: TextStyle(fontSize: 35, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 60),
              Form(
                key: controller.formKey,
                child: Column(
                  children: [
                    TraXTextField(
                      labelText: 'New Password',
                      hintText: '',
                      inPutPassword: true,
                      validator: TraxValidatorUtil.validatePassword,
                      controller: controller.newPwdController,
                    ),
                    const SizedBox(height: 20),
                    TraXTextField(
                      labelText: 'Confirm Password',
                      hintText: '',
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
                textStyle: TextStyle(
                  color: Colors.black,
                  fontSize: 24.0,
                  fontWeight: FontWeight.w700,
                ),
                expand: true,
                onPressed: () => controller.resetPwd(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
