import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tra_x/common/global.dart';
import 'package:tra_x/common/widgets/trax_button.dart';
import 'package:tra_x/common/widgets/trax_text_field.dart';
import 'package:video_player/video_player.dart';

import 'verification_page.dart';

/// 创建账号
class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  VideoPlayerController? _controller;
  TextEditingController emailController = TextEditingController();

  @override
  void initState() {
    _controller = VideoPlayerController.asset('assets/mp4/x-series_h264_854x480_30fps_20crf.mp4')
      ..initialize().then((_) {
        _controller!.setLooping(true);
        _controller!.setVolume(0.0);
        _controller!.play();
        setState(() {});
      });
    super.initState();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 返回按钮
            Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: SvgPicture.asset('assets/images/back_sign_up.svg', width: 35, height: 35),
                ),
              ],
            ),
            const SizedBox(height: 40),
            // title
            Text('Create an Account', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            // google login
            _logoButton('assets/images/logo googleg 48dp.png', 'Continue with Google'),
            SizedBox(height: 10),
            // facebook login
            _logoButton('assets/images/Facebook Logo.png', 'Continue with Facebook'),
            Padding(padding: const EdgeInsets.symmetric(vertical: 40), child: _orWidget()),
            // input
            TraXTextField(labelText: 'Email', hintText: '',controller: emailController),
            const SizedBox(height: 40),
            _signupButton(),
            // By continuing, you are agreeing to our Terms of Services and Privacy Policy.
            const SizedBox(height: 24),
            _termsOfService(),
          ],
        ),
      ),
    );
  }

  // 暂时先复制login_page的代码,等以后复用组件
  Widget _logoButton(String image, String text, {VoidCallback? onPressed}) {
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
            style: TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // 暂时复制login_page的代码,等以后复用组件
  Widget _orWidget() {
    return Row(
      children: [
        Expanded(child: Divider(color: Color(0xFF5E5E5E))),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('OR', style: TextStyle(color: Color(0xFF949494), fontSize: 14)),
        ),
        Expanded(child: Divider(color: Color(0xFF5E5E5E))),
      ],
    );
  }

  Widget _signupButton() {
    return TraxButton(
      borderRadius: Global.traXborderRadius,
      minimumSize: const Size(170, 51),
      backgroundColor: WidgetStateProperty.all<Color?>(Color(0xFFC0C0C0)),
      onPressed: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => VerificationPage()));
      },
      child: Text(
        'Sign up',
        style: TextStyle(color: Colors.black, fontSize: 24.0, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _termsOfService() {
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 14, color: Color(0xFFDADADA)),
        children: [
          TextSpan(text: 'By continuing, you are agreeing to our '),
          // 下划线
          TextSpan(
            text: 'Terms of Services',
            style: TextStyle(decoration: TextDecoration.underline, decorationColor: Color(0xFFDADADA)),
          ),
          TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy.',
            style: TextStyle(decoration: TextDecoration.underline, decorationColor: Color(0xFFDADADA)),
          ),
        ],
      ),
    );
  }
}
