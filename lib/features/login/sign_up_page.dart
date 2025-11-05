import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tra_x/common/global.dart';
import 'package:tra_x/common/widget/button.dart';
import 'package:video_player/video_player.dart';

/// 创建账号
class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  VideoPlayerController? _controller;

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
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 返回按钮
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: SvgPicture.asset('assets/images/back_sign_up.svg', width: 35, height: 35),
            ),
            const SizedBox(height: 40),
            Text('Create an Account', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _logoButton('assets/images/logo googleg 48dp.png', 'Continue with Google'),
            SizedBox(height: 10),
            _logoButton('assets/images/Facebook Logo.png', 'Continue with Facebook'),
          ],
        ),
      ),
    );
  }

  // 暂时先复制login_page的代码,等以后复用组件
  Widget _logoButton(String image, String text, {VoidCallback? onPressed}) {
    return MyElevatedButton(
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
}
