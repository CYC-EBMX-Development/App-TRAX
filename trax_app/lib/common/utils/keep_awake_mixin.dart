import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the device screen awake for the whole lifetime of a [State] and,
/// crucially on iOS, RE-ASSERTS the wakelock every time the app returns
/// from the background.
///
/// Why a one-shot `WakelockPlus.enable()` is not enough on iOS:
/// iOS resets `UIApplication.shared.isIdleTimerDisabled` back to `false`
/// on every background → foreground transition (incoming notification,
/// Control Centre pull-down, brief app switch, etc.). So a wakelock set
/// once in `initState` silently stops working after the first such event
/// and the screen auto-locks mid-activity — exactly what testers saw
/// while a lap session was running.
///
/// Usage: add `with KeepAwakeMixin<MyPage>` to the `State` class. Do NOT
/// also call `WakelockPlus.enable()/disable()` yourself — the mixin owns
/// the full lifecycle (enable on mount, re-enable on resume, disable on
/// dispose) provided your `initState`/`dispose` call `super`.
mixin KeepAwakeMixin<T extends StatefulWidget> on State<T> {
  AppLifecycleListener? _keepAwakeLifecycle;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _keepAwakeLifecycle = AppLifecycleListener(
      // Re-assert on resume; iOS may have cleared it while backgrounded.
      onResume: () => WakelockPlus.enable(),
    );
  }

  @override
  void dispose() {
    _keepAwakeLifecycle?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }
}
