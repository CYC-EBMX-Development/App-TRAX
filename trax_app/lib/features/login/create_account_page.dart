import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common/network/trax_api.dart';
import '../../common/utils/trax_validator_util.dart';
import '../../common/widgets/trax_button.dart';
import '../../common/widgets/trax_dialog.dart';
import '../../common/widgets/trax_or_widget.dart';
import '../../common/widgets/trax_page_widget.dart';
import '../../common/widgets/trax_text_field.dart';
import '../../global.dart';
import '../../routers/trax_router.dart';
import 'login_page_controller.dart';
import 'widgets/login_with_button.dart';
import 'widgets/terms_and_service_widget.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class CreateAccountPageBinding implements Bindings {
  @override
  void dependencies() {
    Get.put(CreateAccountController());
  }
}

class CreateAccountController extends GetxController {
  final TextEditingController emailController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  @override
  void onInit() {
    if (Global.skipRule) {
      emailController.text = Global.skipRuleEmail;
    }
    super.onInit();
  }

  Future<void> toVerificationPage() async {
    if (!formKey.currentState!.validate()) {
      return;
    }

    final resp = await TraxApi.verifyEmail(email: emailController.text);
    if (!resp.isSuccess()) {
      TraxDialog.messageTopDialog(resp.message, false);
      return;
    }

    TraxRouter.toCreatePwdPage(emailController.text, (pwd) async {
      // Verification step temporarily hidden — register directly after password.
      final result = await TraxApi.registerByPwd(
        email: emailController.text,
        password: pwd,
        verificationCode: '',
      );
      if (!result.isSuccess()) {
        TraxDialog.messageTopDialog(result.message, result.flag);
        return;
      }
      TraxDialog.messageTopDialog('Sign up successful', true);
      TraxRouter.toLoginPageOffAll();
    });
  }
}

class CreateAccountPage extends GetView<CreateAccountController> {
  const CreateAccountPage({super.key});

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '702', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      appBar: TraxAppBar(),
      resizeToAvoidBottomInset: false,
      extendBodyBehindAppBar: true,
      body: TraxPageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Create an Account', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 50),
            // Third-party sign-up buttons (Google / Apple / Facebook) are
            // hidden for now; will be re-enabled later.
            Form(
              key: controller.formKey,
              child: TraxTextField(
                hintText: 'Email',
                controller: controller.emailController,
                validator: TraxValidatorUtil.validateEmail,
                fillColor: Colors.white,
                textColor: Colors.black,
              ),
            ),
            const SizedBox(height: 30),
            TraxButton.filled(
              text: 'Sign up',
              textStyle: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black, fontSize: 20),
              expand: true,
              backgroundColor: const Color(0xFFFFB800),
              overlayColor: const Color(0xFFF8C645),
              onPressed: () => controller.toVerificationPage(),
            ),
            const SizedBox(height: 16),
            const TermsAndServiceWidget(),
          ],
        ),
      ),
    );
  }
}
