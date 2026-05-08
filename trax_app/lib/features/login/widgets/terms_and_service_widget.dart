import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class TermsAndServiceWidget extends StatelessWidget {
  const TermsAndServiceWidget({super.key, this.onTapTerms, this.onTapPrivacy});

  final void Function()? onTapTerms;
  final void Function()? onTapPrivacy;

  final Color _textColor = const Color(0xFF2F2F2F);

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 14, color: _textColor, fontWeight: FontWeight.w500),
        children: [
          const TextSpan(text: 'By continuing, you are agreeing to our '),
          TextSpan(
            text: 'Terms of Services',
            style: TextStyle(decoration: TextDecoration.underline, decorationColor: _textColor),
            recognizer: TapGestureRecognizer()
              ..onTap = onTapTerms ?? () {},
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy.',
            style: TextStyle(decoration: TextDecoration.underline, decorationColor: _textColor),
            recognizer: TapGestureRecognizer()
              ..onTap = onTapPrivacy ?? () {},
          ),
        ],
      ),
    );
  }
}
