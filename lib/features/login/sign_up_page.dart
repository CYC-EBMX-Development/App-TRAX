import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:tra_x/common/utils/trax_navigation_util.dart';
import 'package:tra_x/common/utils/trax_validator_util.dart';
import 'package:tra_x/common/widgets/trax_button.dart';
import 'package:tra_x/common/widgets/trax_or_widget.dart';
import 'package:tra_x/common/widgets/trax_text_field.dart';
import 'package:tra_x/features/login/widgets/login_with_button.dart';
import 'package:video_player/video_player.dart';

import 'verification_page.dart';

// binding page class
class SignUpPageBinding implements Bindings {
  @override
  void dependencies() {
    Get.put(SignUpController());
  }
}

// SignUpPage Controller class extends GetxController
class SignUpController extends GetxController {
  VideoPlayerController? videoPlayerController;
  final TextEditingController emailController = TextEditingController();

  final videoPlayerInit = false.obs;

  final formKey = GlobalKey<FormState>();

  @override
  void onInit() {
    videoPlayerController = VideoPlayerController.asset('assets/mp4/login.mp4')
      ..initialize().then((_) {
        videoPlayerController!.setLooping(true);
        videoPlayerController!.setVolume(0.0);
        videoPlayerController!.play();
        videoPlayerInit.value = true;
      });
    super.onInit();
  }

  @override
  void onClose() {
    videoPlayerController?.dispose();
    super.onClose();
  }

  void toVerificationPage() {
    if (!formKey.currentState!.validate()) {
      return;
    }
    TraxNaviUtil.push(VerificationPage(email: emailController.text));
  }
}

/// 创建账号
class SignUpPage extends GetView<SignUpController> {
  const SignUpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
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
          Container(color: Colors.black54, alignment: Alignment.center),
          _signUpWidget(),
        ],
      ),
    );
  }

  Widget _signUpWidget() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 返回按钮
            Row(
              children: [
                GestureDetector(
                  onTap: () => TraxNaviUtil.pop(),
                  child: SvgPicture.asset('assets/svg/return.svg', width: 35, height: 35),
                ),
              ],
            ),
            const SizedBox(height: 40),
            // title
            Text('Create an Account', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 50),
            // google login
            LoginWithButton(type: LoginButtonType.google, onPressed: () {}),
            SizedBox(height: 10),
            // facebook login
            LoginWithButton(type: LoginButtonType.google, onPressed: () {}),
            Padding(padding: const EdgeInsets.symmetric(vertical: 40), child: TraxOrWidget()),
            // input
            Form(
              key: controller.formKey,
              child: TraXTextField(
                labelText: 'Email',
                hintText: '',
                controller: controller.emailController,
                validator: TraxValidatorUtil.validateEmail,
              ),
            ),
            const SizedBox(height: 30),
            TraxButton.filled(
              text: 'Sign up',
              textStyle: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 24),
              expand: true,
              backgroundColor: Colors.white,
              onPressed: () => controller.toVerificationPage(),
            ),
            const SizedBox(height: 16),
            _TermsAndServiceWidget(
              onTapTerms: () {
                // 跳转到服务条款页面
                debugPrint('点击了服务条款');
              },
              onTapPrivacy: () {
                // 跳转到隐私协议页面
                debugPrint('点击了隐私协议');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TermsAndServiceWidget extends StatelessWidget {
  const _TermsAndServiceWidget({required this.onTapTerms, required this.onTapPrivacy});

  final void Function() onTapTerms;
  final void Function() onTapPrivacy;

  final Color _textColor = const Color(0xFFDADADA);

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 14, color: _textColor),
        children: [
          TextSpan(text: 'By continuing, you are agreeing to our '),
          // 下划线
          TextSpan(
            text: 'Terms of Services',
            style: TextStyle(
              decoration: TextDecoration.underline,
              decorationColor: Color(0xFFDADADA),
            ),
            recognizer: TapGestureRecognizer()..onTap = onTapTerms,
          ),
          TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy.',
            style: TextStyle(
              decoration: TextDecoration.underline,
              decorationColor: Color(0xFFDADADA),
            ),
            recognizer: TapGestureRecognizer()..onTap = onTapPrivacy,
          ),
        ],
      ),
    );
  }
}
