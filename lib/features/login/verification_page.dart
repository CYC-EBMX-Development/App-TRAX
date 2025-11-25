import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:pinput/pinput.dart';
import 'package:tra_x/common/widgets/trax_button.dart';

import '../../common/global.dart';
import '../../common/network/app_response.dart';
import '../../common/network/trax_api.dart';
import '../../common/widgets/trax_dialog.dart';

class VerificationPage extends StatefulWidget {
  const VerificationPage({super.key});

  @override
  State<VerificationPage> createState() => _VerificationState();
}

class _VerificationState extends State<VerificationPage> {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();
  Timer? _timer;
  int _seconds = 0;
  bool _hasError = false;

  late final String _email;

  /// 跳转的回调
  ///
  /// 如果校验成功，则跳转到下一个页面
  late final void Function(String code) _onNext;

  @override
  void initState() {
    super.initState();
    _email = Get.parameters['email'] ?? '';
    _onNext = Get.arguments;
    _pinFocusNode.addListener(() {
      if (_pinFocusNode.hasFocus) {
        setState(() {
          _hasError = false;
        });
      }
    });
    _sendCode();
  }

  Future<void> _sendCode() async {
    AppResponse response = await TraxApi.sendCode(email: _email);
    TraxDialog.messageTopDialog(response.message, response.flag);
  }

  void _startTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _seconds--;
        if (_seconds == 0) {
          _timer?.cancel();
        }
      });
    });
  }

  /// 输入完成直接回调
  Future<void> _onInputComplete(String code) async {
    _onNext(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: EdgeInsets.all(20.0),
        child: SingleChildScrollView(child: _mainPage()),
      ),
    );
  }

  Widget _mainPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 40),
        GestureDetector(
          onTap: () {
            Navigator.pop(context);
          },
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
          _email,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        SizedBox(height: 30),
        Pinput(
          focusNode: _pinFocusNode,
          controller: _pinController,
          length: 6,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          defaultPinTheme: PinTheme(
            width: 50,
            height: 60,
            textStyle: TextStyle(fontSize: 24, color: Colors.white),
            decoration: BoxDecoration(
              border: Border.all(color: _hasError ? Colors.red : Color(0xFF454545)),
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
          onCompleted: _onInputComplete,
        ),
        SizedBox(height: 25),
        Row(
          children: [
            _seconds <= 0
                ? TraxButton.outlined(
                    onPressed: () {
                      _sendCode();
                      setState(() => _seconds = 30);
                      _startTimer();
                      //CircularProgressIndicator();
                    },
                    child: Text(
                      'Get a new code',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : _circularProgress(),
            SizedBox(width: 20),
            if (_seconds > 0)
              Text('Try again in 0:$_seconds', style: TextStyle(color: Color(0xFFA0A0A0))),
          ],
        ),
        SizedBox(height: 15),
        Text(
          'Open email app',
          style: TextStyle(
            decoration: TextDecoration.underline,
            decorationColor: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
            decorationThickness: 2,
          ),
        ),
      ],
    );
  }

  Widget _circularProgress() {
    return Container(
      width: 142.5,
      height: 40,
      margin: EdgeInsets.fromLTRB(0, 4, 0, 4),
      decoration: BoxDecoration(
        border: Border.all(color: Color(0xFF919191), width: 1),
        borderRadius: BorderRadius.circular(Global.borderRadius),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF919191)),
            ),
          ),
        ],
      ),
    );
  }
}
