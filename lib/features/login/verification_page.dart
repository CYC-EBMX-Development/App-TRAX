import 'package:flutter/material.dart';
import 'package:tra_x/common/widgets/trax_button.dart';
import 'package:tra_x/common/widgets/trax_text_field.dart';
import 'dart:async';

import '../../common/global.dart';

class VerificationPage extends StatefulWidget {
  const VerificationPage({super.key});

  @override
  State<VerificationPage> createState() => _VerificationState();
}

class _VerificationState extends State<VerificationPage> {
  List<FocusNode> focusNodes = List.generate(6, (index) => FocusNode());
  String message = '';
  Timer? _timer;
  int _seconds = 0;

  void setMessage({String? value}){
    setState(() {
      message = value??'';
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _seconds--;
        print('object----------'+_seconds.toString());
        if(_seconds==0){
          _timer?.cancel();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: EdgeInsets.all(20.0),
        child:SingleChildScrollView(
            child:_mainPage()
        ),
      ),
    );
  }

  Widget _mainPage(){
    double height = MediaQuery.of(context).size.height;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 40),
        GestureDetector(
          onTap: () {
            Navigator.pop(context);
          },
          child: Image.asset(
            'assets/images/Return.png',
            width: 35,
            height: 35,
          ),
        ),
        SizedBox(height: 30),
        Text('Verification', style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 30),
        Text('Please enter the 6-digit code we sent to', style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xffDADADA),
          ),
        ),
        Text('jonchan@cycmotor.com', style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SingleDigitInput(focusNode: focusNodes[0],nextFocus:(){focusNodes[1].requestFocus();}),
            SingleDigitInput(focusNode: focusNodes[1],nextFocus:(){focusNodes[2].requestFocus();}),
            SingleDigitInput(focusNode: focusNodes[2],nextFocus:(){focusNodes[3].requestFocus();}),
            SingleDigitInput(focusNode: focusNodes[3],nextFocus:(){focusNodes[4].requestFocus();}),
            SingleDigitInput(focusNode: focusNodes[4],nextFocus:(){focusNodes[5].requestFocus();}),
            SingleDigitInput(focusNode: focusNodes[5],nextFocus:(){}),
          ],
        ),
        SizedBox(height: 25),
        Row(children: [
          _seconds <= 0 ? TraxButton(
            borderRadius: Global.traXborderRadius,
            onPressed: () {
              setState(()=>_seconds = 3);
              _startTimer();
              //CircularProgressIndicator();
            },
            backgroundColor: WidgetStateProperty.all<Color?>(Colors.transparent),
            side: WidgetStateProperty.all(
              BorderSide(color: Colors.white, width: 1),
            ),
            child: Text('Get a new code' , style: TextStyle(
              color: Colors.white,
              fontSize: 13.0,
              fontWeight: FontWeight.w600,)),
          ): _CircularProgress (),
          SizedBox(width: 20),
          if(_seconds > 0) Text('Try again in 0:${_seconds}',style: TextStyle(color: Color(0xFFA0A0A0),)),
        ],),
        SizedBox(height: 15),
        SizedBox(height: height/3,
          child: Text(message,style: TextStyle(color: Colors.red),),
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

  Widget _CircularProgress (){
    return Container(
      width: 142.5,
      height: 40,
      margin: EdgeInsets.fromLTRB(0, 4, 0, 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: Color(0xFF919191),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(Global.traXborderRadius),
      ),
      child: Row(mainAxisAlignment:MainAxisAlignment.center,children: [
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF919191)),
          ),
        ),
      ],),
    );
  }
}