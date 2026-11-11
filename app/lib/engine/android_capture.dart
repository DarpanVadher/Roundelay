import 'dart:io';
import 'package:flutter/services.dart';

/// Thrown when this phone's audio cannot be shared; [message] is meant to be shown to the person as is.
class CaptureException implements Exception {
  CaptureException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Turns the native error codes (see MainActivity.kt) into something a person can act on.
String captureErrorMessage(String code, String? detail) => switch (code) {
      'unsupported' => "Sharing this phone's audio needs Android 10 or newer.",
      'denied_mic' =>
        'Android needs the audio permission to capture sound from other apps (no microphone is used). Allow it and try again.',
      'denied' => "Screen-capture permission was declined. Allow it so this phone's audio can be shared.",
      'busy' => 'Sharing is already starting. Try again in a moment.',
      _ => 'Could not start audio capture${detail == null || detail.isEmpty ? '.' : ': $detail'}',
    };

/// Android only: captures what other apps are playing and feeds it to the host engine, through a foreground
/// service (a notification stays visible while sharing). Elsewhere the engine captures system audio itself.
class AndroidCapture {
  static const _channel = MethodChannel('mpsp/capture');

  static bool get isNeeded => Platform.isAndroid;

  /// Asks for the needed permissions and screen-capture consent, then starts capturing into the engine source
  /// [sourceId]. Throws [CaptureException] if anything is declined or fails.
  static Future<void> start(int sourceId) async {
    try {
      await _channel.invokeMethod<void>('start', {'sourceId': sourceId});
    } on PlatformException catch (e) {
      throw CaptureException(captureErrorMessage(e.code, e.message));
    } on MissingPluginException {
      throw CaptureException("This build can't capture audio on this device.");
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on Object {
      // not running
    }
  }
}
