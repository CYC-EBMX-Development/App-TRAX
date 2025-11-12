import 'package:flutter/material.dart';

class Global {
  // 不要构造函数
  Global._();

  static String appName = 'TraX';
  static String traXFontFamily = 'ChakraPetch';
  static double traXborderRadius = 5.0;
  static Color traXthemeColor = Colors.black;

  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static BuildContext? get context => navigatorKey.currentState?.context;
}
