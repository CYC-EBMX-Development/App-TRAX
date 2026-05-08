import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common/widgets/trax_button.dart';
import '../../routers/trax_router.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class ResetPwdSuccessPageBinding implements Bindings {
  @override
  void dependencies() {
    Get.put(ResetPwdSuccessController());
  }
}

class ResetPwdSuccessController extends GetxController {
  void toLoginPage() async {
    await TraxRouter.toLoginPageOffAll();
  }
}

class ResetPwdSuccessPage extends GetView<ResetPwdSuccessController> {
  const ResetPwdSuccessPage({super.key});

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '707', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              const Text(
                'Reset Password',
                style: TextStyle(fontSize: 35, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 60),
              const Icon(Icons.check_circle_outline, size: 120, color: Colors.black),
              const SizedBox(height: 50),
              const Text(
                'Password Updated',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              const Text(
                'Your password has been updated.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TraxButton.filled(
                text: 'Login',
                textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black),
                expand: true,
                onPressed: () => controller.toLoginPage(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
