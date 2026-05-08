import 'dart:async';

class TraxThrottle {
  static final Map<String, bool> _throttled = {};

  static void throttle(String key, Duration duration, Function callback) {
    if (_throttled[key] == true) return;
    _throttled[key] = true;
    callback();
    Timer(duration, () => _throttled.remove(key));
  }
}
