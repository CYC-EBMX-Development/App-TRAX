import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../common/models/user_model.dart';
import '../../../common/widgets/trax_button.dart';
import '../../../common/widgets/trax_dialog.dart';

enum LoginButtonType {
  google(title: 'Continue with Google', icon: 'assets/svg/google_logo.svg', label: 'Google'),
  facebook(title: 'Continue with Facebook', icon: 'assets/svg/facebook_logo.svg', label: 'Facebook'),
  apple(title: 'Continue with Apple', icon: 'assets/svg/apple_logo.svg', label: 'Apple');

  final String title;
  final String icon;
  final String label;

  const LoginButtonType({required this.title, required this.icon, required this.label});

  bool isGoogle() => this == LoginButtonType.google;
  bool isFacebook() => this == LoginButtonType.facebook;
  bool isApple() => this == LoginButtonType.apple;
}

class LoginWithButton extends StatelessWidget {
  const LoginWithButton({super.key, required this.type, this.onSuccess});

  final LoginButtonType type;
  final void Function(LoginModel model)? onSuccess;

  Future<void> _loginWithGoogle() async {
    // TODO: Integrate Google Sign-In SDK
    TraxDialog.messageTopDialog('Google login not yet implemented', false);
  }

  Future<void> _loginWithApple() async {
    // TODO: Integrate Apple Sign-In SDK
    TraxDialog.messageTopDialog('Apple login not yet implemented', false);
  }

  Future<void> _loginWithFacebook() async {
    // TODO: Integrate Facebook Login SDK
    TraxDialog.messageTopDialog('Facebook login not yet implemented', false);
  }

  @override
  Widget build(BuildContext context) {
    return TraxButton.filled(
      expand: true,
      padding: const EdgeInsets.symmetric(vertical: 12),
      backgroundColor: const Color(0xFFEEEEEE),
      overlayColor: const Color(0xFFDDDDDD),
      boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 4))],
      onPressed: () async {
        if (type.isGoogle()) {
          await _loginWithGoogle();
        } else if (type.isApple()) {
          await _loginWithApple();
        } else if (type.isFacebook()) {
          await _loginWithFacebook();
        }
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(width: 50),
          SvgPicture.asset(
            type.icon,
            width: 24,
            height: 24,
            colorFilter: const ColorFilter.mode(Color(0xFF565656), BlendMode.srcIn),
          ),
          const SizedBox(width: 40),
          Text(
            type.title,
            style: const TextStyle(color: Color(0xFF565656), fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
