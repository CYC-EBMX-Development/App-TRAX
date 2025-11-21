import 'package:flutter/material.dart';

/// 屏幕适配工具类
class TraxScreenUtil {
  TraxScreenUtil._();

  static late BuildContext _ctx;

  static init(BuildContext context) {
    _ctx = context;
  }

  /// 按照屏幕百分比获取宽度
  ///
  /// 范围：0-1
  static double width(double percent) {
    return MediaQuery.of(_ctx).size.width * percent;
  }

  /// 按照屏幕百分比获取高度
  ///
  /// 范围：0-1
  static double height(double percent) {
    return MediaQuery.of(_ctx).size.height * percent;
  }
}