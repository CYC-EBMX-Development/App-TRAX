import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

/// Gesture recognizer set that lets `GoogleMap` win pan/zoom gestures even
/// when nested inside scrollable parents (CustomScrollView, ListView, etc).
///
/// Usage:
/// ```dart
/// GoogleMap(
///   ...,
///   gestureRecognizers: kMapGestureRecognizers,
/// )
/// ```
final Set<Factory<OneSequenceGestureRecognizer>> kMapGestureRecognizers =
    <Factory<OneSequenceGestureRecognizer>>{
  Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
};
