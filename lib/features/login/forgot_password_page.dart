import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tra_x/common/global.dart';
import 'package:tra_x/common/utils/trax_log_util.dart';
import 'package:tra_x/common/utils/trax_navigation_util.dart';
import 'package:tra_x/common/widgets/trax_button.dart';
import 'package:tra_x/common/widgets/trax_text_field.dart';
import 'package:tra_x/features/login/reset_password_page.dart';
import 'package:tra_x/features/login/verification_page.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final TextEditingController _controller = TextEditingController();

  void _navigate() {
    TraxLogUtil.debug('跳转页面');
    TraxNaviUtil.push(
      VerificationPage(
        email: _controller.text,
        onNext: () {
          TraxNaviUtil.push(ResetPasswordPage());
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: SvgPicture.asset(
                      'assets/images/back_sign_up.svg',
                      width: 35,
                      height: 35,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              const Text(
                "Forgot Password",
                style: TextStyle(fontSize: 35, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 60),
              Text(
                'Enter Email Address',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 20),
              TraXTextField(
                labelText: 'Email',
                hintText: 'Email Address',
                controller: _controller,
              ),
              SizedBox(height: 40),
              _sendButton(() => _navigate()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sendButton(void Function() onSend) {
    return TraxButton(
      borderRadius: Global.traXborderRadius,
      minimumSize: const Size(170, 51),
      backgroundColor: WidgetStateProperty.all<Color?>(Colors.white),
      onPressed: onSend,
      child: Text(
        'Send',
        style: TextStyle(
          color: Colors.black,
          fontSize: 24.0,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
