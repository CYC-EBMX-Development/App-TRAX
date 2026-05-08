import 'package:get/get.dart';

class TraxNaviUtil {
  TraxNaviUtil._();

  static Future<T?>? pushNamed<T>(String page, {dynamic arg, Map<String, String>? parameters}) {
    return Get.toNamed(page, arguments: arg, parameters: parameters);
  }

  static Future<T?>? pushAndRemoveAll<T>(String page, {dynamic arg}) {
    return Get.offAllNamed(page, arguments: arg);
  }

  static void pop<T>({T? result}) {
    Get.back(result: result);
  }
}
