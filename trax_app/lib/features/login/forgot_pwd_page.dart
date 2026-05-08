import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common/utils/trax_validator_util.dart';
import '../../common/widgets/trax_button.dart';
import '../../common/widgets/trax_page_widget.dart';
import '../../common/widgets/trax_text_field.dart';
import '../../global.dart';
import '../../routers/trax_router.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class ForgotPwdPageBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(ForgotPwdPageController());
  }
}

class ForgotPwdPageController extends GetxController {
  final TextEditingController emailController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  @override
  void onInit() {
    if (Global.skipRule) {
      emailController.text = Global.skipRuleEmail;
    }
    super.onInit();
  }

  @override
  void onClose() {
    emailController.dispose();
    super.onClose();
  }

  void navigate() {
    if (!formKey.currentState!.validate()) {
      return;
    }
    TraxRouter.toVerificationPage(emailController.text, (String code) {
      TraxRouter.toResetPwdPage(emailController.text, code);
    });
  }
}

class ForgotPwdPage extends GetView<ForgotPwdPageController> {
  const ForgotPwdPage({super.key});

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '705', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      appBar: TraxAppBar(),
      extendBodyBehindAppBar: true,
      body: TraxPageBody(
        showBackground: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Forgot Password', style: TextStyle(fontSize: 35, fontWeight: FontWeight.bold)),
            const SizedBox(height: 60),
            const Text('Enter Email Address', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            Form(
              key: controller.formKey,
              child: TraxTextField(
                hintText: 'Email Address',
                controller: controller.emailController,
                validator: TraxValidatorUtil.validateEmail,
              ),
            ),
            const SizedBox(height: 40),
            TraxButton.filled(
              text: 'Send',
              backgroundColor: Colors.white,
              textStyle: const TextStyle(color: Colors.black, fontSize: 24.0, fontWeight: FontWeight.w700),
              expand: true,
              onPressed: () => controller.navigate(),
            ),
          ],
        ),
      ),
    );
  }
}
