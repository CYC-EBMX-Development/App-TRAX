import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:tra_x/common/widgets/trax_button.dart';
import 'package:tra_x/common/widgets/trax_text.dart';
import 'package:tra_x/routers/trax_router.dart';

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
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Spacer(),
              TraxText(
                'Reset Password',
                style: TextStyle(fontSize: 35, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 60),
              SvgPicture.asset('assets/svg/success.svg', height: 120, width: 120),
              const SizedBox(height: 50),
              TraxText(
                'Password Updated',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TraxText(
                'Your password has been updated.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              Spacer(),
              TraxButton.filled(
                text: 'Login',
                textStyle: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
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
