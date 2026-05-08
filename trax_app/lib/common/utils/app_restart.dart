/// Decouples the "restart app" action from main.dart so any widget can trigger
/// a full app restart without importing main.dart.
class AppRestart {
  AppRestart._();

  static Future<void> Function()? _handler;

  /// Called once in AppWrapper.initState to register the restart callback.
  static void register(Future<void> Function() handler) {
    _handler = handler;
  }

  /// Triggers a full widget-tree restart. No-op if not yet registered.
  static Future<void> restart() => _handler?.call() ?? Future.value();
}
