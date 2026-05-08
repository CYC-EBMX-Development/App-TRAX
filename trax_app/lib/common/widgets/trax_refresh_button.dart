import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import '../utils/app_restart.dart';

/// Small refresh icon button that triggers reassemble + full app restart.
class TraxRefreshButton extends StatefulWidget {
  const TraxRefreshButton({super.key});

  @override
  State<TraxRefreshButton> createState() => _TraxRefreshButtonState();
}

class _TraxRefreshButtonState extends State<TraxRefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    _spin.forward(from: 0);
    // Reassemble first (picks up hot-reloaded code if flutter is attached)
    if (kDebugMode) {
      WidgetsBinding.instance.reassembleApplication();
    }
    // Then full widget-tree restart
    await AppRestart.restart();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: RotationTransition(
        turns: _spin,
        child: const Icon(Icons.refresh_rounded, size: 18, color: Colors.black45),
      ),
    );
  }
}

/// Builds a plain AppBar title widget.
Widget traxTitle(String text, {TextStyle? style}) {
  return Text(text, style: style ?? const TextStyle(fontWeight: FontWeight.w700));
}
