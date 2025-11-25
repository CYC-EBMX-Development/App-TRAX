import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 导航工具类
class TraxNaviUtil {
  TraxNaviUtil._();

  static Future<T?>? push<T>(Widget page) => Get.to<T>(() => page);

  static Future<T?>? pushNamed<T>(String routeName, {dynamic arg,Map<String, String>? parameters}) =>
      Get.toNamed(routeName, arguments: arg, parameters: parameters);

  static Future<T?>? pushAndRemoveAll<T>(String newRouteName) => Get.offAllNamed(newRouteName);

  static void pop<T>({dynamic result}) => Get.back<T>(result: result);
}
