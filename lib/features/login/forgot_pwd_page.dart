import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_x/common/utils/trax_validator_util.dart';
import 'package:tra_x/common/widgets/trax_button.dart';
import 'package:tra_x/common/widgets/trax_text_field.dart';
import 'package:tra_x/routers/trax_router.dart';

// Get binding class
class ForgotPwdPageBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(ForgotPwdPageController());
  }
}

// Get controller class
class ForgotPwdPageController extends GetxController {
  final TextEditingController emailController = TextEditingController();

  final formKey = GlobalKey<FormState>();

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
              const Text(
                "Forgot Password",
                style: TextStyle(fontSize: 35, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 60),
              Text(
                'Enter Email Address',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 20),
              Form(
                key: controller.formKey,
                child: Column(
                  children: [
                    TraXTextField(
                      labelText: 'Email',
                      hintText: 'Email Address',
                      controller: controller.emailController,
                      validator: TraxValidatorUtil.validateEmail,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 40),
              _sendButton(() => controller.navigate()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sendButton(void Function() onSend) {
    return TraxButton.filled(
      text: 'Send',
      backgroundColor: Colors.white,
      textStyle: TextStyle(color: Colors.black, fontSize: 24.0, fontWeight: FontWeight.w700),
      expand: true,
      onPressed: onSend,
    );
  }
}
