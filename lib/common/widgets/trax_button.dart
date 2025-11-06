import 'package:flutter/material.dart';

import '../global.dart';

class TraxButton extends StatelessWidget {
  /// 有选中效果的按钮。有亮色和暗色
  const TraxButton({
    super.key,
    this.onPressed,
    this.style,
    this.autofocus = false,
    this.borderRadius,
    this.text,
    this.child,
    this.textFontSize = 32,
    this.textFontWeight = FontWeight.normal,
    this.textColor = Colors.white,
    this.backgroundColor,
    this.minimumSize = const Size(100.0, 40.0),
    this.side,
  });

  final WidgetStateProperty<BorderSide?>? side;
  final WidgetStateProperty<Color?>? backgroundColor;
  final Color textColor;
  final FontWeight textFontWeight;
  final double textFontSize;
  final VoidCallback? onPressed;
  final ButtonStyle? style;
  final bool autofocus;
  final Size minimumSize;

  /// 圆角
  /// null || 大于等于高(1000)：圆形矩形按钮
  /// 大于0小于高：     圆角矩形按钮
  /// 0：              矩形按钮
  final double? borderRadius;
  final String? text;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: style ?? getButtonStyle(),
      autofocus: autofocus,
      child: child ??
          (text != null
              ? Text(
            text!,
            style: TextStyle(
              color: textColor,
              decoration: TextDecoration.none,
              fontSize: textFontSize,
              fontWeight: textFontWeight,
              fontFamily: Global.traXFontFamily,
            ),
            textAlign: TextAlign.left,
          )
              : null),
    );
  }
  ButtonStyle getButtonStyle() {
    return ButtonStyle(
      minimumSize: WidgetStateProperty.all<Size>(minimumSize),
      side: side,
      backgroundColor:  backgroundColor,
      shape: borderRadius == null
          ? null
          : WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(borderRadius!)),
        ),
      ),
    );
  }
}