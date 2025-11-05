import 'package:flutter/material.dart';

import '../../common/global.dart';
import '../../common/widget/button.dart';
import '../../common/widget/textField.dart';

class VerificationPage extends StatefulWidget {
  const VerificationPage({super.key});

  @override
  State<VerificationPage> createState() => _VerificationState();
}

class _VerificationState extends State<VerificationPage> {
  List<FocusNode> focusNodes = List.generate(6, (index) => FocusNode());


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
            SingleDigitInput(focusNode: focusNodes[4],nextFocus:(){}),
          ],
        ),
        SizedBox(height: 25),
        MyElevatedButton(
          borderRadius: Global.traXborderRadius,
          minimumSize: const Size(140, 37),
          onPressed: () {
          },
          backgroundColor: WidgetStateProperty.all<Color?>(Colors.transparent),
          side: WidgetStateProperty.all(
            BorderSide(color: Colors.white, width: 1),
          ),
          child: Text('Get a new code' , style: TextStyle(
            color: Colors.white,
            fontSize: 13.0,
            fontWeight: FontWeight.w600,)),
        ),
        SizedBox(height: height/3),
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
}