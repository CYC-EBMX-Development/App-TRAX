import 'dart:async';

typedef DebouncerCallback = void Function();

class _AppDebouncerOperation {
  final Timer timer;

  const _AppDebouncerOperation({required this.timer});
}

/// 节流功能
///
/// 特定时间内只响应第一次
class TraxThrottle {
  static final Map<String, _AppDebouncerOperation> _operations = {};

  static void throttle(String tag, Duration duration, DebouncerCallback callback) {
    if (_operations.containsKey(tag)) {
      return;
    }
    _operations[tag] = _AppDebouncerOperation(
      timer: Timer(duration, () {
        _operations.remove(tag);
      }),
    );
    callback();
  }
}
