import 'package:flutter/material.dart';
import 'package:tra_x/common/widgets/trax_button.dart';
import 'package:pinput/pinput.dart';
import 'dart:async';
import 'package:dio/dio.dart';

import '../../common/dio/dio.dart';
import '../../common/global.dart';

class VerificationPage extends StatefulWidget {
  const VerificationPage({super.key,required this.email ,this.onNext});

  final String email;
  /// 跳转的回调
  ///
  /// 如果校验成功，则跳转到下一个页面
  final void Function()? onNext;

  @override
  State<VerificationPage> createState() => _VerificationState();
}

class _VerificationState extends State<VerificationPage> {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();
  String message = '';
  Timer? _timer;
  int _seconds = 0;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _pinFocusNode.addListener((){
      if(_pinFocusNode.hasFocus){
        setState(() {
          _hasError = false;
        });
      }
    });
    _sendCode();
  }

  Future<void> _sendCode() async {
    Response response = await sendCode(
      widget.email);
    print('object'+response.toString());
  }

  void setMessage({String? value}) {
    setState(() {
      message = value ?? '';
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _seconds--;
        print('object----------$_seconds');
        if (_seconds == 0) {
          _timer?.cancel();
        }
      });
    });
  }

  /// 输入完成
  Future<void> _onInputComplete(String code) async {
    String example = '123456'; // 暂时写死，要从用户输入获取
    Response response = await verifyCode(widget.email,code);
    print('object'+response.toString());
    if (code == example) {
      print('验证成功');
    } else {
      _pinController.text = '';
      _pinFocusNode.unfocus();
      setState(() {
        _hasError = true;
      });
    }
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
    double height = MediaQuery.of(context).size.height;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 40),
        GestureDetector(
          onTap: () {
            Navigator.pop(context);
          },
          child: Image.asset('assets/images/Return.png', width: 35, height: 35),
        ),
        SizedBox(height: 30),
        Text(
          'Verification',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 30),
        Text(
          'Please enter the 6-digit code we sent to',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xffDADADA),
          ),
        ),
        Text(
          'jonchan@cycmotor.com',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
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
            textStyle: TextStyle(
              fontSize: 24,
              color: Colors.white,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: _hasError? Colors.red :Color(0xFF454545)),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          focusedPinTheme: PinTheme(
            width: 50,
            height: 60,
            textStyle: TextStyle(
              fontSize: 24,
              color: Colors.white,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onCompleted: (pin) {
            print('验证码输入完成: $pin');
            _onInputComplete(pin);
          },
        ),
        SizedBox(height: 25),
        Row(
          children: [
            _seconds <= 0
                ? TraxButton(
                    borderRadius: Global.traXborderRadius,
                    onPressed: () {
                      _sendCode();
                      setState(() => _seconds = 30);
                      _startTimer();
                      //CircularProgressIndicator();
                    },
                    backgroundColor: WidgetStateProperty.all<Color?>(
                      Colors.transparent,
                    ),
                    side: WidgetStateProperty.all(
                      BorderSide(color: Colors.white, width: 1),
                    ),
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
              Text(
                'Try again in 0:$_seconds',
                style: TextStyle(color: Color(0xFFA0A0A0)),
              ),
          ],
        ),
        SizedBox(height: 15),
        SizedBox(
          height: height / 3,
          child: Text(message, style: TextStyle(color: Colors.red)),
        ),
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
        borderRadius: BorderRadius.circular(Global.traXborderRadius),
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
