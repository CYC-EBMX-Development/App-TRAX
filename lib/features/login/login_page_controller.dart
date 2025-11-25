import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_x/common/network/app_response.dart';
import 'package:tra_x/common/network/trax_api.dart';
import 'package:tra_x/common/widgets/trax_dialog.dart';
import 'package:tra_x/routers/trax_router.dart';
import 'package:video_player/video_player.dart';

// Get binding class
class LoginPageBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(LoginPageController());
  }
}

// Get controller class
class LoginPageController extends GetxController {
  VideoPlayerController? videoPlayerController;
  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();

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

  void login() async {
    if (!formKey.currentState!.validate()) {
      return;
    }
    AppResponse response = await TraxApi.loginWithPasswd(
      username: emailController.text,
      password: passwordController.text,
    );
    TraxDialog.messageTopDialog(response.message, response.flag);
  }

  void toForgotPwdPage() async {
    await videoPlayerController?.pause();
    await TraxRouter.toForgotPwdPage();
    await videoPlayerController?.play();
  }

  void toCreateAccountPage()  async {
    await videoPlayerController?.pause();
    await TraxRouter.toCreateAccountPage();
    await videoPlayerController?.play();
  }
}
