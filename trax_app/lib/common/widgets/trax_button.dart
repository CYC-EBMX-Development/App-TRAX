import 'package:flutter/material.dart';
import '../utils/trax_debouncer.dart';
import '../utils/trax_navigation_util.dart';

class TraxButton extends StatelessWidget {
  const TraxButton({
    super.key,
    required this.child,
    required this.onPressed,
    required this.style,
    this.expand = false,
    this.size,
    this.boxShadow,
    this.shadowBorderRadius,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final ButtonStyle style;
  final bool expand;
  final Size? size;
  final List<BoxShadow>? boxShadow;
  final double? shadowBorderRadius;

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
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius))),
        minimumSize: const WidgetStatePropertyAll(Size.zero),
        overlayColor: WidgetStatePropertyAll(overlayColor),
      ),
      onPressed: onPressed,
      child: child ?? Text(text ?? '', style: textStyle, textAlign: TextAlign.center),
    );
  }

  factory TraxButton.filled({
    String? text,
    Widget? child,
    VoidCallback? onPressed,
    TextStyle textStyle = const TextStyle(color: Colors.black),
    EdgeInsets padding = const EdgeInsets.all(8),
    Color? backgroundColor = Colors.white,
    Color? overlayColor = Colors.black12,
    Color borderColor = Colors.transparent,
    double borderRadius = 20,
    bool expand = false,
    Size? size,
    List<BoxShadow>? boxShadow,
  }) {
    return TraxButton(
      expand: expand,
      size: size,
      boxShadow: boxShadow,
      shadowBorderRadius: borderRadius,
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(backgroundColor),
        padding: WidgetStatePropertyAll(padding),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          side: BorderSide(color: borderColor),
          borderRadius: BorderRadius.circular(borderRadius),
        )),
        minimumSize: const WidgetStatePropertyAll(Size.zero),
        overlayColor: WidgetStatePropertyAll(overlayColor),
      ),
      onPressed: onPressed,
      child: child ?? Text(text ?? '', style: textStyle, textAlign: TextAlign.center),
    );
  }

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
        padding: WidgetStatePropertyAll(padding),
        overlayColor: WidgetStatePropertyAll(overlayColor),
        minimumSize: const WidgetStatePropertyAll(Size.zero),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: BorderSide(color: borderColor, strokeAlign: BorderSide.strokeAlignInside, width: borderWidth),
        )),
      ),
      onPressed: onPressed,
      child: child ?? Text(text ?? '', style: textStyle, textAlign: TextAlign.center),
    );
  }

  @override
  Widget build(BuildContext context) {
    final button = TextButton(
      onPressed: onPressed == null ? null : () => _onPressed(),
      style: style,
      child: _child(),
    );
    if (boxShadow == null || boxShadow!.isEmpty) return button;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shadowBorderRadius != null ? BorderRadius.circular(shadowBorderRadius!) : null,
        boxShadow: boxShadow,
      ),
      child: button,
    );
  }

  Widget _child() {
    if (size != null) return SizedBox(width: size!.width, height: size!.height, child: Center(child: child));
    return expand ? Row(children: [Expanded(child: child)]) : child;
  }

  void _onPressed() {
    TraxThrottle.throttle(onPressed.hashCode.toString(), const Duration(milliseconds: 500), onPressed!);
  }
}

class TraxReturnButton extends StatelessWidget {
  const TraxReturnButton({super.key, this.onPressed});
  final void Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return TraxButton(
      onPressed: () => onPressed != null ? onPressed!() : TraxNaviUtil.pop(),
      style: const ButtonStyle(
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        overlayColor: WidgetStatePropertyAll(Colors.transparent),
        minimumSize: WidgetStatePropertyAll(Size.zero),
      ),
      child: const Icon(Icons.arrow_back_ios_new, size: 24, color: Colors.black),
    );
  }
}
