import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tra_x/common/widgets/trax_button.dart';
import 'package:tra_x/common/widgets/trax_text_field.dart';

class ResetPwdPage extends StatefulWidget {
  const ResetPwdPage({super.key});

  @override
  State<ResetPwdPage> createState() => _ResetPwdPageState();
}

class _ResetPwdPageState extends State<ResetPwdPage> {
  final TextEditingController _newPwdController = TextEditingController();
  final TextEditingController _confirmPwdController = TextEditingController();

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
              TraXTextField(
                labelText: 'Password',
                hintText: 'Password',
                inPutPassword: true,
                controller: _newPwdController,
              ),
              SizedBox(height: 20),
              TraXTextField(
                labelText: 'Password',
                hintText: 'Password',
                inPutPassword: true,
                controller: _confirmPwdController,
              ),
              SizedBox(height: 40),
              _confirmButton(() {}),
            ],
          ),
        ),
      ),
    );
  }

  Widget _confirmButton(void Function() onConfirm) {
    return TraxButton.outlined(
      onPressed: onConfirm,
      child: Text(
        'Confirm',
        style: TextStyle(
          color: Colors.black,
          fontSize: 24.0,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
