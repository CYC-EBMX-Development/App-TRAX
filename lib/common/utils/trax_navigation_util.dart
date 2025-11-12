import 'package:flutter/material.dart';
import 'package:tra_x/common/global.dart';

/// 导航工具类
class TraxNaviUtil {
  TraxNaviUtil._();

  static void push(Widget page) {
    Navigator.push(
      Global.context!,
      MaterialPageRoute(builder: (context) => page),
    );
  }

  static void pushReplace(Widget page) {
    Navigator.pushReplacement(
      Global.context!,
      MaterialPageRoute(builder: (context) => page),
    );
  }

  static void pushAndRemoveUntil(Widget page) {
    Navigator.pushAndRemoveUntil(
      Global.context!,
      MaterialPageRoute(builder: (context) => page),
      (route) => false,
    );
  }

  static void pop() {
    Navigator.pop(Global.context!);
  }
}
