import 'package:flutter/foundation.dart';

class TraxLogUtil {
  TraxLogUtil._();

  static void debug(String msg) {
    _log(msg, 'D');
  }

  static void info(String msg) {
    _log(msg, 'I');
  }

  static void warning(String msg) {
    _log(msg, 'W');
  }

  static void error(String msg) {
    _log(msg, 'E');
  }

  static void _log(String msg, String logLevel) {
    DateTime now = DateTime.now();
    String timestamp =
        '${_padLeftTime(now.hour)}:${_padLeftTime(now.minute)}:${_padLeftTime(now.second)}';
    String callMethod = _formatStackTrace(StackTrace.current);
    // 太长会被截断的问题(看情况处理)，因为网络请求的日志都在 app_logger_interceptor.dart 中
    // 这里只是开发者自己打印的日志
    // 比如与硬件通信的日志，就需要处理
    final log = '[$timestamp][$logLevel][$callMethod] : $msg';

    // 如果没有Get框架，改成
    if (kDebugMode) debugPrint(log);
    // Get.log(log);
  }

  static String _padLeftTime(int num) {
    return num.toString().padLeft(2, '0');
  }

  static String _formatStackTrace(StackTrace stackTrace) {
    String myFind = stackTrace
        .toString()
        .split('\n')
        .firstWhere((value) => value.startsWith('#2'), orElse: () => '');
    String findLine = myFind.split('/').last;
    return findLine;
  }
}
