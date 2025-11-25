import 'package:flutter/material.dart';
import 'package:tra_x/common/widgets/trax_button.dart';
import 'package:tra_x/common/widgets/trax_text.dart';
import 'package:tra_x/routers/trax_router.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(image: AssetImage('assets/images/login.png'), fit: BoxFit.fill),
        ),
        child: Padding(padding: EdgeInsets.all(15.0), child: _mainColumn()),
      ),
    );
  }

  Widget _mainColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Spacer(flex: 12),
        TraxText('EBMX', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 50)),
        TraxText('TRA-X', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 90)),
        Spacer(flex: 8),
        TraxText(
          'Spark Adventure, Track Every Thrill',
          style: TextStyle(color: Color(0xff909090), fontWeight: FontWeight.w600, fontSize: 32),
        ),
        Spacer(flex: 3),
        _buttons(),
        Spacer(flex: 3),
      ],
    );
  }

  Widget _buttons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        Expanded(
          child: TraxButton.filled(
            text: 'Join Us',
            textStyle: TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.bold),
            onPressed: () {},
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: TraxButton.outlined(
            text: 'Log in',
            textStyle: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            borderColor: Colors.white,
            onPressed: () => TraxRouter.toLoginPage(),
          ),
        ),
      ],
    );
  }
}
