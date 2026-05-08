import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common/utils/trax_validator_util.dart';
import '../../common/widgets/trax_button.dart';
import '../../common/widgets/trax_dialog.dart';
import '../../common/widgets/trax_page_widget.dart';
import '../../common/widgets/trax_text_field.dart';
import '../../global.dart';
import '../../routers/trax_router.dart';
import 'widgets/terms_and_service_widget.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class CreatePwdPageBinding implements Bindings {
  @override
  void dependencies() {
    Get.put(CreatePwdPageController());
  }
}

class CreatePwdPageController extends GetxController {
  TextEditingController pwdController = TextEditingController();
  TextEditingController confirmPwdController = TextEditingController();

  final formKey = GlobalKey<FormState>();

  late final String email;
  late final Function(String pwd) onSuccess;

  @override
  void onInit() {
    email = Get.parameters['email'] ?? '';
    onSuccess = Get.arguments;
    if (Global.skipRule) {
      pwdController.text = Global.skipRulePwd;
      confirmPwdController.text = Global.skipRulePwd;
    }
    super.onInit();
  }

  @override
  void onClose() {
    pwdController.dispose();
    confirmPwdController.dispose();
    super.onClose();
  }

  void signUp() async {
    if (!formKey.currentState!.validate()) {
      return;
    }
    if (pwdController.text != confirmPwdController.text) {
      TraxDialog.messageTopDialog('Please make sure your passwords match', false);
      return;
    }

    if (Global.skipRule) {
      TraxDialog.messageTopDialog('Sign up success', true);
      TraxRouter.toLoginPageOffAll();
      return;
    }

    onSuccess(pwdController.text);
  }
}

class CreatePwdPage extends GetView<CreatePwdPageController> {
  const CreatePwdPage({super.key});

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '704', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      appBar: TraxAppBar(),
      resizeToAvoidBottomInset: false,
      extendBodyBehindAppBar: true,
      body: TraxPageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Create a password', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 50),
            Form(
              key: controller.formKey,
              child: Column(
                children: [
                  TraxTextField(
                    hintText: 'Password - Must be 8 characters',
                    inPutPassword: true,
                    controller: controller.pwdController,
                    validator: TraxValidatorUtil.validatePassword,
                    fillColor: Colors.white,
                    textColor: Colors.black,
                  ),
                  const SizedBox(height: 20),
                  TraxTextField(
                    hintText: 'Confirm Password',
                    inPutPassword: true,
                    controller: controller.confirmPwdController,
                    validator: TraxValidatorUtil.validatePassword,
                    fillColor: Colors.white,
                    textColor: Colors.black,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            TraxButton.filled(
              text: 'Sign up',
              textStyle: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black, fontSize: 24),
              expand: true,
              backgroundColor: const Color(0xFFFFB800),
              overlayColor: const Color(0xFFF8C645),
              onPressed: () => controller.signUp(),
            ),
            const SizedBox(height: 20),
            const TermsAndServiceWidget(),
          ],
        ),
      ),
    );
  }
}
