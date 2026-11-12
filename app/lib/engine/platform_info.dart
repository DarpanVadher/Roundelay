import 'dart:io';

/// Picks the address other devices should use to reach this one. Prefers common home/office LAN ranges, then
/// anything non-loopback, non-link-local. Returns null when there is no usable network.
String? pickLanIp(Iterable<String> candidates) {
  final ok = candidates
      .where((a) => !a.startsWith('127.') && !a.startsWith('169.254.'))
      .toList();
  bool inRange(String a, bool Function(List<int>) f) {
    final p = a.split('.').map(int.tryParse).toList();
    return p.length == 4 && !p.contains(null) && f(p.cast<int>());
  }

  for (final test in <bool Function(List<int>)>[
    (p) => p[0] == 192 && p[1] == 168,
    (p) => p[0] == 10,
    (p) => p[0] == 172 && p[1] >= 16 && p[1] <= 31,
  ]) {
    for (final a in ok) {
      if (inRange(a, test)) return a;
    }
  }
  return ok.isEmpty ? null : ok.first;
}

Future<String?> findLanIp() async {
  final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  return pickLanIp(ifaces.expand((i) => i.addresses).map((a) => a.address));
}

/// Where the host identity key lives. TODO(mobile): use path_provider on Android/iOS.
String appDataDir() {
  final env = Platform.environment;
  if (Platform.isWindows && env['APPDATA'] != null) {
    return '${env['APPDATA']}\\MultiPhonePlayer';
  }
  if (env['XDG_CONFIG_HOME'] != null) {
    return '${env['XDG_CONFIG_HOME']}/multiphone-player';
  }
  if (env['HOME'] != null) return '${env['HOME']}/.config/multiphone-player';
  return '${Directory.systemTemp.path}/multiphone-player';
}

/// Every IPv4 address this device currently has (used to spot the one a freshly started hotspot adds).
Future<Set<String>> allIpv4() async {
  final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  return ifaces.expand((i) => i.addresses).map((a) => a.address).toSet();
}

/// Waits briefly for a hotspot interface to appear and returns its address (an address that was not in [before]).
Future<String?> findNewLanIp(
  Set<String> before, {
  Duration wait = const Duration(seconds: 4),
}) async {
  final end = DateTime.now().add(wait);
  while (true) {
    final now = await allIpv4();
    final added = now.difference(before);
    final ip = pickLanIp(added);
    if (ip != null) return ip;
    if (DateTime.now().isAfter(end)) return null;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}
