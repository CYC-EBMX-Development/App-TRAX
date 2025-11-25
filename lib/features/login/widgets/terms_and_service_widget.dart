import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tra_x/common/utils/trax_log_util.dart';

class TermsAndServiceWidget extends StatelessWidget {
  const TermsAndServiceWidget({super.key, this.onTapTerms, this.onTapPrivacy});

  final void Function()? onTapTerms;
  final void Function()? onTapPrivacy;

  final Color _textColor = const Color(0xFFDADADA);

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 14, color: _textColor),
        children: [
          TextSpan(text: 'By continuing, you are agreeing to our '),
          // 下划线
          TextSpan(
            text: 'Terms of Services',
            style: TextStyle(
              decoration: TextDecoration.underline,
              decorationColor: Color(0xFFDADADA),
            ),
            recognizer: TapGestureRecognizer()
              ..onTap =
                  onTapTerms ??
                  () {
                    // 跳转到服务条款页面
                    TraxLogUtil.debug('点击了服务条款');
                  },
          ),
          TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy.',
            style: TextStyle(
              decoration: TextDecoration.underline,
              decorationColor: Color(0xFFDADADA),
            ),
            recognizer: TapGestureRecognizer()
              ..onTap =
                  onTapPrivacy ??
                  () {
                    // 跳转到隐私协议页面
                    TraxLogUtil.debug('点击了隐私协议');
                  },
          ),
        ],
      ),
    );
  }
}
