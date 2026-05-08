import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common/utils/trax_validator_util.dart';
import '../../common/widgets/trax_button.dart';
import '../../common/widgets/trax_or_widget.dart';
import '../../common/widgets/trax_page_widget.dart';
import '../../common/widgets/trax_text_field.dart';
import 'login_page_controller.dart';
import 'widgets/login_with_button.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class LoginPage extends GetView<LoginPageController> {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '701', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: TraxAppBar(
          title: const Text(
            'TRAX',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 28, color: Colors.black),
          ),
          centerTitle: false,
          showLeading: false,
        ),
        resizeToAvoidBottomInset: false,
        extendBodyBehindAppBar: true,
        body: TraxPageBody(
          child: SingleChildScrollView(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Login',
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.w500, color: Color(0xFF545454)),
              ),
              const SizedBox(height: 40),
              Form(
                key: controller.formKey,
                child: Column(
                  children: [
                    TraxTextField(
                      hintText: 'Email address',
                      controller: controller.emailController,
                      validator: TraxValidatorUtil.validateEmail,
                      fillColor: Colors.white,
                      textColor: Colors.black,
                    ),
                    const SizedBox(height: 20),
                    TraxTextField(
                      hintText: 'Password',
                      inPutPassword: true,
                      controller: controller.passwordController,
                      validator: TraxValidatorUtil.validateLoginPassword,
                      fillColor: Colors.white,
                      textColor: Colors.black,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TraxButton.text(
                    text: 'Forgot Password?',
                    textStyle: const TextStyle(fontSize: 16, color: Color(0xFF848484)),
                    onPressed: () => controller.toForgotPwdPage(),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              TraxButton.filled(
                text: 'Login',
                textStyle: const TextStyle(color: Colors.black, fontSize: 20),
                expand: true,
                backgroundColor: const Color(0xFFFFB800),
                overlayColor: const Color(0xFFF8C645),
                onPressed: () => controller.login(),
              ),
              const SizedBox(height: 15),
              const TraxOrWidget(color: Color(0xFF878787)),
              const SizedBox(height: 16),
              if (GetPlatform.isAndroid)
                LoginWithButton(
                  type: LoginButtonType.google,
                  onSuccess: (model) => controller.loginSuccess(model),
                )
              else if (GetPlatform.isIOS)
                LoginWithButton(
                  type: LoginButtonType.apple,
                  onSuccess: (model) => controller.loginSuccess(model),
                ),
              const SizedBox(height: 10),
              LoginWithButton(
                type: LoginButtonType.facebook,
                onSuccess: (model) => controller.loginSuccess(model),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account?",
                    style: TextStyle(color: Color(0xFF4A4A4A), fontSize: 14),
                  ),
                  TraxButton.text(
                    text: 'Sign up.',
                    textStyle: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF555555)),
                    onPressed: () => controller.toCreateAccountPage(),
                  ),
                ],
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}
