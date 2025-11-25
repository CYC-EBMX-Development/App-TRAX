import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:tra_x/common/utils/trax_debouncer.dart';
import 'package:tra_x/common/utils/trax_navigation_util.dart';

/// 按钮组件
///
/// 按钮：包含点击事件的组件即为按钮
/// 可自定义宽高、或者填满整个父容器、内边距等
class TraxButton extends StatelessWidget {
  const TraxButton({
    super.key,
    required this.child,
    required this.onPressed,
    required this.style,
    this.expand = false,
    this.size,
  });

  final Widget child;

  /// 没有点击事件则不可点击
  final VoidCallback? onPressed;

  final ButtonStyle style;

  /// 是否填充满整个父容器，在需要单独一行的时候很好用
  final bool expand;

  /// 宽度, 如果设置宽高则expand属性失效
  final Size? size;

  /// 文字按钮,即背景为透明色。
  /// 暂时没有IOS风格，按下时改变字体本身的颜色
  factory TraxButton.text({
    String? text,
    Widget? child,
    VoidCallback? onPressed,
    TextStyle textStyle = const TextStyle(color: Colors.white),
    EdgeInsets padding = const EdgeInsets.all(8),
    Color? overlayColor = Colors.white10,
    double borderRadius = 4,
    bool expand = false,
    Size? size,
  }) {
    return TraxButton(
      expand: expand,
      size: size,
      style: ButtonStyle(
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: WidgetStatePropertyAll(padding),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
        ),
        minimumSize: const WidgetStatePropertyAll(Size.zero),
        overlayColor: WidgetStatePropertyAll(overlayColor), // 触摸时的背景色
      ),
      onPressed: onPressed,
      child: child ?? Text(text ?? '', style: textStyle, textAlign: TextAlign.center),
    );
  }

  /// 填充按钮
  factory TraxButton.filled({
    String? text,
    Widget? child,
    VoidCallback? onPressed,
    TextStyle textStyle = const TextStyle(color: Colors.black),
    EdgeInsets padding = const EdgeInsets.all(8),
    Color? backgroundColor = Colors.white,
    Color? overlayColor = Colors.black12,
    Color borderColor = Colors.transparent,
    double borderWidth = 1,
    double borderRadius = 5,
    bool expand = false,
    Size? size,
  }) {
    return TraxButton(
      expand: expand,
      size: size,
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(backgroundColor),
        padding: WidgetStatePropertyAll(padding),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            side: BorderSide(color: borderColor, width: borderWidth),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
        minimumSize: const WidgetStatePropertyAll(Size.zero),
        overlayColor: WidgetStatePropertyAll(overlayColor), // 触摸时的背景色
      ),
      onPressed: onPressed,
      child: child ?? Text(text ?? '', style: textStyle, textAlign: TextAlign.center),
    );
  }

  /// 带边框的按钮
  factory TraxButton.outlined({
    String? text,
    Widget? child,
    VoidCallback? onPressed,
    TextStyle? textStyle,
    EdgeInsets padding = const EdgeInsets.all(8),
    Color? backgroundColor = Colors.transparent,
    Color borderColor = Colors.white,
    Color? overlayColor = Colors.black12,
    double borderRadius = 5,
    double borderWidth = 1,
    bool expand = false,
    Size? size,
  }) {
    return TraxButton(
      expand: expand,
      size: size,
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(backgroundColor),
        // 背景色
        padding: WidgetStatePropertyAll(padding),
        overlayColor: WidgetStatePropertyAll(overlayColor),
        minimumSize: const WidgetStatePropertyAll(Size.zero),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            side: BorderSide(
              color: borderColor,
              strokeAlign: BorderSide.strokeAlignInside,
              width: borderWidth,
            ),
          ),
        ),
      ),
      onPressed: onPressed,
      child: child ?? Text(text ?? '', style: textStyle, textAlign: TextAlign.center),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed == null
          ? null // 默认500ms内只响应一次
          : () => TraxThrottle.throttle(
              onPressed.hashCode.toString(),
              const Duration(milliseconds: 500),
              onPressed!,
            ),
      style: style,
      child: _child(),
    );
  }

  Widget _child() {
    if (size != null) {
      return SizedBox(
        width: size!.width,
        height: size!.height,
        child: Center(child: child),
      );
    }
    return expand ? Row(children: [Expanded(child: child)]) : child;
  }
}

class TraxReturnButton extends StatelessWidget {
  const TraxReturnButton({super.key, this.onPressed});

  final void Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return TraxButton(
      onPressed: () {
        if (onPressed != null) {
          onPressed!();
        } else {
          TraxNaviUtil.pop();
        }
      },
      style: const ButtonStyle(
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        overlayColor: WidgetStatePropertyAll(Colors.transparent),
        minimumSize: WidgetStatePropertyAll(Size.zero),
      ),
      child: SvgPicture.asset('assets/svg/return.svg', width: 35, height: 35),
    );
  }
}
