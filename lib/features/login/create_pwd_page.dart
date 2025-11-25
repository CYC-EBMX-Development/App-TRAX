import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_x/common/network/trax_api.dart';
import 'package:tra_x/common/utils/trax_log_util.dart';
import 'package:tra_x/common/utils/trax_validator_util.dart';
import 'package:tra_x/common/widgets/trax_button.dart';
import 'package:tra_x/common/widgets/trax_dialog.dart';
import 'package:tra_x/common/widgets/trax_or_widget.dart';
import 'package:tra_x/common/widgets/trax_text_field.dart';
import 'package:tra_x/features/login/widgets/terms_and_service_widget.dart';
import 'package:tra_x/routers/trax_router.dart';
import 'package:video_player/video_player.dart';

import 'widgets/login_with_button.dart';

// Get binding page class
class CreatePwdPageBinding implements Bindings {
  @override
  void dependencies() {
    Get.put(CreatePwdPageController());
  }
}

// Get controller class
class CreatePwdPageController extends GetxController {
  VideoPlayerController? videoPlayerController;

  TextEditingController pwdController = TextEditingController();
  TextEditingController passwordController = TextEditingController();

  final videoPlayerInit = false.obs;

  final formKey = GlobalKey<FormState>();

  late final String email;

  late final String verificationCode;

  @override
  void onInit() {
    videoPlayerController = VideoPlayerController.asset('assets/mp4/login.mp4')
      ..initialize().then((_) {
        videoPlayerController!.setLooping(true);
        videoPlayerController!.setVolume(0.0);
        videoPlayerController!.play();
        videoPlayerInit.value = true;
      });
    email = Get.parameters['email'] ?? '';
    verificationCode = Get.parameters['verificationCode'] ?? '';
    TraxLogUtil.debug('create pwd page email: $email verificationCode: $verificationCode');
    super.onInit();
  }

  @override
  void onClose() {
    videoPlayerController?.dispose();
    super.onClose();
  }

  void signUp() async {
    if (!formKey.currentState!.validate()) {
      return;
    }
    if (pwdController.text != passwordController.text) {
      TraxDialog.messageTopDialog('Please make sure your passwords match', false);
      return;
    }

    final password = pwdController.text;
    final result = await TraxApi.registerByPwd(
      email: email,
      password: password,
      verificationCode: verificationCode,
    );
    TraxDialog.messageTopDialog(result.message, result.flag);
    if (result.isSuccess()) {
      TraxRouter.toLoginPageOffAll();
    }
  }
}

// Get view class
class CreatePwdPage extends GetView<CreatePwdPageController> {
  const CreatePwdPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          _mainPage(),
        ],
      ),
    );
  }

  Widget _mainPage() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TraxReturnButton(),
            const SizedBox(height: 40),
            // title
            Text('Create a password', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            SizedBox(height: 50),
            Form(
              key: controller.formKey,
              child: Column(
                children: [
                  TraXTextField(
                    labelText: 'Password - Must be 8 characters',
                    hintText: '',
                    inPutPassword: true,
                    controller: controller.pwdController,
                    validator: TraxValidatorUtil.validatePassword,
                  ),
                  const SizedBox(height: 20),
                  TraXTextField(
                    labelText: 'Confirm Password',
                    hintText: '',
                    inPutPassword: true,
                    controller: controller.passwordController,
                    validator: TraxValidatorUtil.validatePassword,
                  ),
                ],
              ),
            ),
            SizedBox(height: 30),
            TraxButton.filled(
              text: 'Sign up',
              textStyle: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 24),
              expand: true,
              backgroundColor: Colors.white,
              onPressed: () => controller.signUp(),
            ),
            SizedBox(height: 20),
            TermsAndServiceWidget(),
            SizedBox(height: 40),
            TraxOrWidget(),
            SizedBox(height: 16),
            LoginWithButton(type: LoginButtonType.google, onPressed: () {}),
            SizedBox(height: 10),
            LoginWithButton(type: LoginButtonType.facebook, onPressed: () {}),
            SizedBox(height: 10),
            LoginWithButton(type: LoginButtonType.apple, onPressed: () {}),
            SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
