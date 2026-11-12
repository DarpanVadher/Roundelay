import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_info.dart';

/// Wi-Fi details a host can put in the pairing QR so guests can join the hotspot and pair in one scan.
/// They travel as extra query parameters on the pairing link (`ws`, `wp`, `wt`); the audio engine ignores them.
class WifiCredentials {
  const WifiCredentials({
    required this.ssid,
    this.password = '',
    this.local = false,
  });
  final String ssid;
  final String password; // empty means an open network
  final bool
  local; // came from this app's own hotspot (Android), not typed by the user

  bool get isOpen => password.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is WifiCredentials &&
      other.ssid == ssid &&
      other.password == password;
  @override
  int get hashCode => Object.hash(ssid, password);
}

/// Adds Wi-Fi details (and, for a hotspot on another interface, the address guests should dial) to a pairing link.
String composeLink(String link, {WifiCredentials? wifi, String? hostIp}) {
  var out = link.trim();
  if (hostIp != null) {
    out = out.replaceFirstMapped(
      RegExp(r'([?&]h=)[^:&]+'),
      (m) => '${m[1]}$hostIp',
    );
  }
  if (wifi != null && wifi.ssid.isNotEmpty) {
    out +=
        '&ws=${Uri.encodeQueryComponent(wifi.ssid)}&wt=${wifi.isOpen ? 'nopass' : 'WPA'}';
    if (!wifi.isOpen) out += '&wp=${Uri.encodeQueryComponent(wifi.password)}';
  }
  return out;
}

/// Wi-Fi details carried by a pairing link, or null when it has none.
WifiCredentials? wifiFromLink(String link) {
  final i = link.indexOf('?');
  if (i < 0) return null;
  try {
    final q = Uri.splitQueryString(link.substring(i + 1));
    final ssid = q['ws'];
    if (ssid == null || ssid.isEmpty) return null;
    return WifiCredentials(
      ssid: ssid,
      password: q['wt'] == 'nopass' ? '' : (q['wp'] ?? ''),
    );
  } on Object {
    return null;
  }
}

/// Native Wi-Fi helpers (Android). Other platforms report [supported] false and the UI falls back to showing details.
abstract class WifiBridge {
  /// Can this device start its own hotspot (host) and join a Wi-Fi network from the app (guest)?
  bool get canStartHotspot;
  bool get canJoinWifi;

  /// Starts an app-owned hotspot and returns its name and password. Throws [WifiBridgeException] with a readable message.
  Future<WifiCredentials> startHotspot();
  Future<void> stopHotspot();

  /// Joins [wifi] for this app only (Android shows its own confirmation). Throws [WifiBridgeException].
  Future<void> joinWifi(WifiCredentials wifi);
  Future<void> leaveWifi();
}

class WifiBridgeException implements Exception {
  WifiBridgeException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PlatformWifiBridge implements WifiBridge {
  static const _channel = MethodChannel('mpsp/hotspot');
  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  bool get canStartHotspot => _android;
  @override
  bool get canJoinWifi => _android;

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw WifiBridgeException(e.message ?? 'Wi-Fi request failed.');
    } on MissingPluginException {
      throw WifiBridgeException('This device cannot do that from the app.');
    }
  }

  @override
  Future<WifiCredentials> startHotspot() async {
    final r = await _call<Map<Object?, Object?>>('startHotspot');
    return WifiCredentials(
      ssid: '${r?['ssid'] ?? ''}',
      password: '${r?['password'] ?? ''}',
      local: true,
    );
  }

  @override
  Future<void> stopHotspot() async {
    try {
      await _call<void>('stopHotspot');
    } on WifiBridgeException {
      // Already stopped.
    }
  }

  @override
  Future<void> joinWifi(WifiCredentials wifi) =>
      _call<void>('joinWifi', {'ssid': wifi.ssid, 'password': wifi.password});

  @override
  Future<void> leaveWifi() async {
    try {
      await _call<void>('leaveWifi');
    } on WifiBridgeException {
      // Nothing joined.
    }
  }
}

/// Remembers the Wi-Fi details a host typed, so they are filled in next time. Stored in a small JSON file in the
/// app's data folder; never leaves the device.
abstract class WifiStore {
  Future<({WifiCredentials? wifi, bool include})> load();
  Future<void> save({required WifiCredentials? wifi, required bool include});
}

class FileWifiStore implements WifiStore {
  Future<File?> _file() async {
    try {
      var dir = appDataDir();
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        dir =
            await const MethodChannel('mpsp/hotspot')
                .invokeMethod<String>('filesDir') ??
            dir;
      }
      await Directory(dir).create(recursive: true);
      return File('$dir${Platform.pathSeparator}wifi_share.json');
    } on Object {
      return null;
    }
  }

  @override
  Future<({WifiCredentials? wifi, bool include})> load() async {
    try {
      final f = await _file();
      if (f == null || !await f.exists()) return (wifi: null, include: false);
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final ssid = j['ssid'] as String? ?? '';
      return (
        wifi: ssid.isEmpty
            ? null
            : WifiCredentials(
                ssid: ssid,
                password: j['password'] as String? ?? '',
              ),
        include: j['include'] == true,
      );
    } on Object {
      return (wifi: null, include: false);
    }
  }

  @override
  Future<void> save({
    required WifiCredentials? wifi,
    required bool include,
  }) async {
    try {
      final f = await _file();
      await f?.writeAsString(
        jsonEncode({
          'ssid': wifi?.ssid ?? '',
          'password': wifi?.password ?? '',
          'include': include,
        }),
      );
    } on Object {
      // Not being able to remember is fine; the user can type it again.
    }
  }
}

/// The pairing link without the Wi-Fi details, which is all the audio engine needs.
String stripWifi(String link) {
  final i = link.indexOf('?');
  if (i < 0) return link.trim();
  final kept = link.substring(i + 1).split('&').where((kv) => !(kv.startsWith('ws=') || kv.startsWith('wp=') || kv.startsWith('wt=')));
  return '${link.substring(0, i + 1)}${kept.join('&')}'.trim();
}
