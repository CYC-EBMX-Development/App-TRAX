import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common/widgets/trax_button.dart';
import '../../common/widgets/trax_page_widget.dart';
import '../../global.dart';
import '../../routers/trax_router.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '700', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      appBar: TraxAppBar(
        systemOverlayStyle: SystemUiOverlayStyle.light,
        centerTitle: false,
        showLeading: false,
        title: Text(
          Global.appName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 50, color: Colors.white),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: TraxPageBody(
        backgroundImage: 'assets/images/login.png',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(flex: 4),
            const Text(
              'Get set for\nan electric future.',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 50, color: Colors.white),
            ),
            const Spacer(flex: 8),
            const Text(
              'Pioneers of premium electric bike adventures',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 24),
            ),
            const Spacer(flex: 1),
            _buttons(),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }

  Widget _buttons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        Expanded(
          child: TraxButton.filled(
            text: 'Login',
            textStyle: const TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.bold),
            onPressed: () => TraxRouter.toLoginPageOffAll(),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: TraxButton.outlined(
            text: 'Sign up',
            textStyle: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            borderColor: Colors.white,
            onPressed: () => TraxRouter.toCreateAccountPage(),
          ),
        ),
      ],
    );
  }
}
