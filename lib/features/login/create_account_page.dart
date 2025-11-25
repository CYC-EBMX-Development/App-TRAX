import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_x/common/utils/trax_validator_util.dart';
import 'package:tra_x/common/widgets/trax_button.dart';
import 'package:tra_x/common/widgets/trax_or_widget.dart';
import 'package:tra_x/common/widgets/trax_text_field.dart';
import 'package:tra_x/features/login/widgets/login_with_button.dart';
import 'package:tra_x/routers/trax_router.dart';
import 'package:video_player/video_player.dart';

import 'widgets/terms_and_service_widget.dart';

// binding page class
class CreateAccountPageBinding implements Bindings {
  @override
  void dependencies() {
    Get.put(CreateAccountController());
  }
}

class CreateAccountController extends GetxController {
  VideoPlayerController? videoPlayerController;
  final TextEditingController emailController = TextEditingController();

  final videoPlayerInit = false.obs;

  final formKey = GlobalKey<FormState>();

  @override
  void onInit() {
    emailController.text = '18673298768@163.com'; // 测试账号, 暂时不能用
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

    TraxRouter.toVerificationPage(emailController.text, (code) {
      TraxRouter.toCreatePwdPage(emailController.text, code);
    });
  }
}

/// 创建账号
class CreateAccountPage extends GetView<CreateAccountController> {
  const CreateAccountPage({super.key});

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TraxReturnButton(),
            const SizedBox(height: 40),
            // title
            Text('Create an Account', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 50),
            LoginWithButton(type: LoginButtonType.google),
            SizedBox(height: 10),
            LoginWithButton(type: LoginButtonType.facebook),
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
            TermsAndServiceWidget(),
          ],
        ),
      ),
    );
  }
}
