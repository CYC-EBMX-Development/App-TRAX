import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:pinput/pinput.dart';
import 'package:tra_x/common/utils/trax_navigation_util.dart';
import 'package:tra_x/common/widgets/trax_button.dart';
import 'package:tra_x/common/widgets/trax_text.dart';

import '../../common/network/app_response.dart';
import '../../common/network/trax_api.dart';
import '../../common/widgets/trax_dialog.dart';

class VerificationPageBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(VerificationPageController());
  }
}

class VerificationPageController extends GetxController {
  final TextEditingController pinController = TextEditingController();
  final FocusNode pinFocusNode = FocusNode();
  Timer? timer;
  final seconds = 0.obs;

  late final String email;

  /// 跳转的回调
  ///
  /// 如果校验成功，则跳转到下一个页面
  late final void Function(String code) onNext;

  @override
  void onInit() {
    email = Get.parameters['email'] ?? '';
    onNext = Get.arguments;
    pinFocusNode.addListener(() {
      if (pinFocusNode.hasFocus) {}
    });

    super.onInit();
  }

  @override
  void onReady() {
    sendCode();
  }

  Future<void> sendCode() async {
    AppResponse response = await TraxApi.sendCode(email: email);
    TraxDialog.messageTopDialog(response.message, response.flag);
    startTimer();
  }

  void startTimer() {
    seconds.value = 30;
    timer = Timer.periodic(Duration(seconds: 1), (timer) {
      seconds.value--;
      if (seconds.value <= 0) {
        timer.cancel();
      }
    });
  }

  /// 输入完成直接回调
  void onInputComplete(String code) {
    onNext(code);
  }
}

// Create VerificationPage extends GetxView
class VerificationPage extends GetView<VerificationPageController> {
  const VerificationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 40),
            GestureDetector(
              onTap: () => TraxNaviUtil.pop(),
              child: SvgPicture.asset('assets/svg/return.svg', width: 35, height: 35),
            ),
            SizedBox(height: 30),
            Text(
              'Verification',
              style: TextStyle(fontSize: 35, fontWeight: FontWeight.w600, color: Colors.white),
            ),
            SizedBox(height: 30),
            Text(
              'Please enter the 6-digit code we sent to',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xffDADADA)),
            ),
            Text(
              controller.email,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
            ),
            SizedBox(height: 30),
            Pinput(
              focusNode: controller.pinFocusNode,
              controller: controller.pinController,
              length: 6,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              defaultPinTheme: PinTheme(
                width: 50,
                height: 60,
                textStyle: TextStyle(fontSize: 24, color: Colors.white),
                decoration: BoxDecoration(
                  border: Border.all(color: Color(0xFF454545)),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              focusedPinTheme: PinTheme(
                width: 50,
                height: 60,
                textStyle: TextStyle(fontSize: 24, color: Colors.white),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onCompleted: controller.onInputComplete,
            ),
            SizedBox(height: 25),
            Obx(() {
              if (controller.seconds.value <= 0) {
                return TraxButton.outlined(
                  onPressed: () => controller.sendCode(),
                  padding: EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                  overlayColor: Colors.white12,
                  child: Text(
                    'Get a new code',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }
              return TraxText(
                'Try again in 00:${controller.seconds.value}',
                style: TextStyle(color: Color(0xFFA0A0A0)),
              );
            }),
            const Spacer(),
            TraxText(
              'Open email app',
              style: TextStyle(
                decoration: TextDecoration.underline,
                decorationColor: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                decorationThickness: 2,
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
