import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pinput/pinput.dart';

import '../../common/network/app_response.dart';
import '../../common/network/trax_api.dart';
import '../../common/widgets/trax_button.dart';
import '../../common/widgets/trax_dialog.dart';
import '../../common/widgets/trax_page_widget.dart';
import '../../global.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

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
  late final void Function(String code) onNext;

  @override
  void onInit() {
    email = Get.parameters['email'] ?? '';
    onNext = Get.arguments;
    super.onInit();
  }

  @override
  void onReady() {
    sendCode();
  }

  Future<void> sendCode() async {
    if (Global.skipRule) {
      TraxDialog.messageTopDialog('Send code success', true);
      startTimer();
      return;
    }
    AppResponse response = await TraxApi.sendCode(email: email);
    TraxDialog.messageTopDialog(response.message, response.flag);
    startTimer();
  }

  void startTimer() {
    seconds.value = 30;
    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      seconds.value--;
      if (seconds.value <= 0) {
        timer.cancel();
      }
    });
  }

  void onInputComplete(String code) {
    onNext(code);
  }
}

class VerificationPage extends GetView<VerificationPageController> {
  const VerificationPage({super.key});

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '703', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      appBar: TraxAppBar(),
      extendBodyBehindAppBar: true,
      body: TraxPageBody(
        showBackground: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Verification', style: TextStyle(fontSize: 35, fontWeight: FontWeight.w600)),
            const SizedBox(height: 30),
            const Text(
              'Please enter the 6-digit code we sent to',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF616161)),
            ),
            Text(controller.email, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 30),
            Pinput(
              focusNode: controller.pinFocusNode,
              controller: controller.pinController,
              length: 6,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              cursor: Container(width: 1, height: 20, color: Colors.black),
              defaultPinTheme: PinTheme(
                width: 50,
                height: 60,
                textStyle: const TextStyle(fontSize: 24, color: Colors.black),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF454545)),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              focusedPinTheme: PinTheme(
                width: 50,
                height: 60,
                textStyle: const TextStyle(fontSize: 24, color: Colors.black),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF646464), width: 4),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onCompleted: controller.onInputComplete,
            ),
            const SizedBox(height: 25),
            Obx(() {
              if (controller.seconds.value <= 0) {
                return TraxButton.filled(
                  onPressed: () => controller.sendCode(),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                  backgroundColor: const Color(0xFFAEAEAE),
                  overlayColor: const Color(0xFFA2A4A4),
                  child: const Text('Get a new code', style: TextStyle(color: Colors.white, fontSize: 16)),
                );
              }
              return Text(
                'Try again in 00:${controller.seconds.value}',
                style: const TextStyle(color: Color(0xFFA0A0A0)),
              );
            }),
            const Spacer(),
            TraxButton.text(
              onPressed: () {},
              text: 'Open email app',
              overlayColor: Colors.black12,
              textStyle: const TextStyle(
                color: Colors.black,
                decoration: TextDecoration.underline,
                decorationColor: Colors.black,
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
