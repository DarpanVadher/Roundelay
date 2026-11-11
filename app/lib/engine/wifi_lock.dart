import 'dart:io';
import 'package:flutter/services.dart';

/// Android only: keeps the Wi-Fi radio awake while audio is streaming. A sleeping radio makes the router queue
/// packets until the next ~100 ms beacon, which arrives as late bursts and audible glitches. No-op elsewhere
/// (desktops, and tests, which have no native side).
class WifiLock {
  static const _channel = MethodChannel('mpsp/wifi');

  /// Returns what the platform granted ("low-latency", "high-perf", ...) or null when unavailable.
  static Future<String?> acquire() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('acquire');
    } on Object {
      return null; // missing plugin (tests) or a security exception: carry on without it
    }
  }

  static Future<void> release() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('release');
    } on Object {
      // nothing to release
    }
  }
}
