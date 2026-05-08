import 'package:flutter/material.dart';
import 'trax_button.dart';

class TraxAppBar extends AppBar {
  TraxAppBar({
    super.key,
    super.title,
    super.actions,
    super.centerTitle,
    super.systemOverlayStyle,
    this.showLeading = true,
    super.toolbarHeight,
  }) : super(leading: showLeading ? const TraxReturnButton() : null, automaticallyImplyLeading: false);

  final bool showLeading;
}

class TraxPageBody extends StatelessWidget {
  const TraxPageBody({
    super.key,
    required this.child,
    this.backgroundImage = 'assets/images/page_bkg.png',
    this.top = 160,
    this.horizontal = 20,
    this.bottom = 0,
    this.showBackground = true,
  });

  final Widget child;
  final String backgroundImage;
  final double top;
  final double bottom;
  final double horizontal;
  final bool showBackground;

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
    if (!showBackground) {
      return Padding(padding: padding, child: child);
    }
    return Container(
      padding: padding,
      alignment: Alignment.topCenter,
      decoration: BoxDecoration(
        image: DecorationImage(image: AssetImage(backgroundImage), fit: BoxFit.fill),
      ),
      child: child,
    );
  }
}
