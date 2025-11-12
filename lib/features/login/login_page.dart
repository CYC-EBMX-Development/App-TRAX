import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:tra_x/common/widgets/trax_button.dart';
import 'package:tra_x/common/widgets/trax_text_field.dart';
import 'package:tra_x/features/login/forgot_password_page.dart';
import 'package:tra_x/features/login/sign_up_page.dart';
import 'package:tra_x/features/login/verification_page.dart';
import 'package:video_player/video_player.dart';

import '../../common/dio/app_api.dart';
import '../../common/dio/app_response.dart';
import '../../common/global.dart';
import '../../common/utils/validator_util.dart';
import '../../common/widgets/trax_dialog.dart';

// mp4背景视频文件压缩命令
// ffmpeg -i exotek.mp4 -vf "scale=854:480,fps=15" -c:v libx264 -crf 30 -c:a aac -b:a 128k exotek_h264_854x480_15fps_30crf.mp4
// ffmpeg -i x-series.mov -vf "scale=854:480,fps=30" -c:v libx264 -crf 20 -c:a aac -b:a 128k x-series_h264_854x480_30fps_20crf.mp4

class ExotekQuadricyclePage extends StatefulWidget {
  const ExotekQuadricyclePage({super.key});

  @override
  State<ExotekQuadricyclePage> createState() => _SplashPage();
}

class _SplashPage extends State<ExotekQuadricyclePage> {
  VideoPlayerController? _controller;
  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  bool isEmail = false;


  @override
  void initState() {
    super.initState();
    void _validateForm() {
      final isValid = ValidatorUtil.isEmailValid(emailController.text) &&
          passwordController.text.length > 5;
      setState(() => isEmail = isValid);
    }
    emailController.addListener(_validateForm);
    passwordController.addListener(_validateForm);
    if (!kIsWeb && Platform.isWindows) {
    } else {
      _controller =
          VideoPlayerController.asset(
              'assets/mp4/x-series_h264_854x480_30fps_20crf.mp4',
            )
            ..initialize().then((_) {
              _controller!.setLooping(true);
              _controller!.setVolume(0.0);
              _controller!.play();
              setState(() {});
            });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Localizations.maybeLocaleOf(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_controller != null && _controller!.value.isInitialized)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),
            Container(color: Colors.black54, alignment: Alignment.center),
            Padding(
              padding: EdgeInsets.all(20.0),
              child: SingleChildScrollView(child: _mainPage()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _password() {
    return Column(
      children: [
        SizedBox(height: 15),
        TraXTextField(
          labelText: 'Password',
          hintText: 'Password',
          inPutPassword: true,
          controller: passwordController,
        ),
        SizedBox(height: 15),
        Row(
          children: [
            Expanded(child: SizedBox()),
            GestureDetector(
              child: Text(
                'Forgot Password?',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () async {
                await _controller?.pause();
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ForgotPasswordPage()),
                );
                await _controller?.play();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _mainPage() {
    double screenWidth = MediaQuery.of(context).size.width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 40),
        Text(
          'TRA-X',
          style: TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 50),
        Text(
          'Login',
          style: TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 40),
        TraXTextField(
          labelText: 'Email',
          hintText: 'jonchan@cycmotor.com',
          controller: emailController,
        ),
        _password(),
        SizedBox(height: 30),
        TraxButton(
          borderRadius: Global.traXborderRadius,
          minimumSize: Size(screenWidth, 51),
          backgroundColor: isEmail?
            WidgetStateProperty.all<Color?>(Colors.white):
            WidgetStateProperty.all<Color?>(Color(0xFFC0C0C0)),
          onPressed: () async {
            if(!isEmail){
              return;
            }
            AppResponse response = await loginWithPasswd(
              username: emailController.text,
              password: passwordController.text);
            messageTopDialog(context,response.message,response.flag);
            if(response.flag){
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => VerificationPage(email: emailController.text)),
              );
            }
          },
          child: Text(
            'Log in',
            style: TextStyle(
              color: Colors.black,
              fontSize: 24.0,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(height: 15),
        Row(
          children: [
            Expanded(child: Divider(color: Color(0xFF5E5E5E), indent: 20)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'OR',
                style: TextStyle(color: Color(0xFF949494), fontSize: 14),
              ),
            ),
            Expanded(child: Divider(color: Color(0xFF5E5E5E), endIndent: 20)),
          ],
        ),
        SizedBox(height: 10),
        logoButton(
          'assets/images/logo googleg 48dp.png',
          'Continue with Google',
        ),
        SizedBox(height: 10),
        logoButton('assets/images/Facebook Logo.png', 'Continue with Facebook'),
        SizedBox(height: 10),
        logoButton('assets/images/Apple Logo.png', 'Continue with Apple'),
        SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Don’t have an account?',
              style: TextStyle(color: Color(0xFFCBCBCB), fontSize: 14),
            ),
            GestureDetector(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SignUpPage()),
                );
                await _controller!.play();
              },
              child: Text(
                'Sign up.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget logoButton(String image, String text, {VoidCallback? onPressed}) {
    return TraxButton(
      borderRadius: Global.traXborderRadius,
      minimumSize: const Size(170, 51),
      backgroundColor: WidgetStateProperty.all<Color?>(Color(0xFF1A1B1C)),
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(width: 15),
          Image.asset(image, width: 24, height: 24),
          SizedBox(width: 20),
          Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16.0,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

Widget buttonDecoration(Widget child, Color color) {
  return Container(
    decoration: BoxDecoration(
      border: Border.all(color: color, width: 2.0),
      borderRadius: BorderRadius.circular(5.0),
    ),
    child: child,
  );
}
