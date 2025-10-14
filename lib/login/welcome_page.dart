import 'package:flutter/material.dart';

import '../global.dart';
import '../widget/button.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image:  DecorationImage(
            image: AssetImage('assets/images/login.png'),
            fit: BoxFit.fill,
          )
        ),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(15.0),
            child: _mainCloumn(),
          )
        ),
      ),
    );
  }
  Widget _mainCloumn(){
    return Column(
      children: [
        Spacer(flex: 12),
        Text('EBMX',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 50,
          ),
        ),
        Text('TRA-X',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 90,
          ),
        ),
        Spacer(flex: 8),
        Text('Spark Adventure, Track Every Thrill',
          style: TextStyle(
            color: Color(0xff909090),
            fontWeight: FontWeight.w600,
            fontSize: 32,
          ),
        ),
        Spacer(flex: 3),
        SizedBox(
          height: 60,
          child:_buttens(),
        ),
        Spacer(flex: 3),
      ],
    );
  }
  Widget _buttens(){
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        MyElevatedButton(
          borderRadius: traXborderRadius,
          minimumSize: const Size(170, 51),
          onPressed: () {
          },
          child: Text('Join Us' , style: TextStyle(
            color: Colors.black,
            fontSize: 24.0,
            fontWeight: FontWeight.w700,)),
        ),
        MyElevatedButton(
          borderRadius: traXborderRadius,
          minimumSize: const Size(170, 51),
          onPressed: () {
          },
          backgroundColor: WidgetStateProperty.all<Color?>(Colors.transparent),
          side: WidgetStateProperty.all(
            BorderSide(color: Colors.white, width: 1),
          ),
          child: Text('Log in' , style: TextStyle(
            color: Colors.white,
            fontSize: 24.0,
            fontWeight: FontWeight.w700,)),
        ),
      ],
    );
  }
}
