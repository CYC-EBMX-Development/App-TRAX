import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tra_x/common/network/trax_api.dart';
import 'package:tra_x/common/widgets/trax_button.dart';
import 'package:tra_x/routers/trax_router.dart';

enum LoginButtonType {
  google(
    title: 'Continue with Google',
    icon: 'assets/svg/google_logo.svg',
    label: 'Google',
    url: TraxUrl.loginWithGoogle,
  ),
  facebook(
    title: 'Continue with Facebook',
    icon: 'assets/svg/facebook_logo.svg',
    label: 'Facebook',
    url: TraxUrl.loginWithFacebook,
  ),
  apple(
    title: 'Continue with Apple',
    icon: 'assets/svg/apple_logo.svg',
    label: 'Apple',
    url: TraxUrl.loginWithApple,
  );

  final String title;

  final String icon;

  final String label;

  final String url;

  const LoginButtonType({
    required this.title,
    required this.icon,
    required this.label,
    required this.url,
  });
}

// Login with Google, Facebook, Apple ...
class LoginWithButton extends StatelessWidget {
  const LoginWithButton({super.key, required this.type, this.onPressed});

  final LoginButtonType type;

  final void Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return TraxButton.filled(
      expand: true,
      padding: EdgeInsets.symmetric(vertical: 12),
      backgroundColor: Color(0xFF1A1B1C),
      overlayColor: Colors.black45,
      onPressed: onPressed ?? () {
        TraxRouter.toWebViewPage(type.label, TraxApi.getWebLoginUrl(type.url));
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(width: 50),
          SvgPicture.asset(type.icon, width: 24, height: 24),
          SizedBox(width: 40),
          Text(
            type.title,
            style: TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
