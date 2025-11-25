import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_x/common/utils/trax_validator_util.dart';
import 'package:tra_x/common/widgets/trax_button.dart';
import 'package:tra_x/common/widgets/trax_or_widget.dart';
import 'package:tra_x/common/widgets/trax_text_field.dart';
import 'package:tra_x/features/login/login_page_controller.dart';
import 'package:tra_x/features/login/widgets/login_with_button.dart';
import 'package:video_player/video_player.dart';

// GetView
class LoginPage extends GetView<LoginPageController> {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Obx(() {
              if (!controller.videoPlayerInit.value) {
                return SizedBox.expand();
              }
              return FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.videoPlayerController!.value.size.width,
                  height: controller.videoPlayerController!.value.size.height,
                  child: VideoPlayer(controller.videoPlayerController!),
                ),
              );
            }),
            // black shadow
            Container(color: Colors.black54, alignment: Alignment.center),
            SingleChildScrollView(padding: EdgeInsets.all(20), child: _mainPage()),
          ],
        ),
      ),
    );
  }

  Widget _mainPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 40),
        Text(
          'TRA-X',
          style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 50),
        Text(
          'Login',
          style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 40),
        Form(
          key: controller.formKey,
          child: Column(
            children: [
              TraXTextField(
                labelText: 'Email',
                hintText: 'jonchan@cycmotor.com',
                controller: controller.emailController,
                validator: TraxValidatorUtil.validateEmail,
              ),
              const SizedBox(height: 20),
              TraXTextField(
                labelText: 'Password',
                hintText: 'Password',
                inPutPassword: true,
                controller: controller.passwordController,
                validator: TraxValidatorUtil.validatePassword,
              ),
            ],
          ),
        ),

        SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TraxButton.text(
              text: 'Forgot Password?',
              textStyle: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
              onPressed: () => controller.toForgotPwdPage(),
            ),
          ],
        ),
        SizedBox(height: 30),
        TraxButton.filled(
          text: 'Log in',
          textStyle: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 24),
          expand: true,
          backgroundColor: Colors.white,
          onPressed: () => controller.login(),
        ),
        SizedBox(height: 15),
        TraxOrWidget(),
        SizedBox(height: 16),
        LoginWithButton(type: LoginButtonType.google),
        SizedBox(height: 10),
        LoginWithButton(type: LoginButtonType.facebook),
        SizedBox(height: 10),
        LoginWithButton(type: LoginButtonType.apple),
        SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Don’t have an account?',
              style: TextStyle(color: Color(0xFFCBCBCB), fontSize: 14),
            ),
            const SizedBox(width: 5),
            TraxButton.text(
              text: 'Sign up.',
              textStyle: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
              onPressed: () => controller.toSignUpPage(),
            ),
          ],
        ),
      ],
    );
  }
}
