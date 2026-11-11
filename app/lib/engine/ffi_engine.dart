// HostEngine / GuestEngine backed by the Rust core. A 100 ms timer drains the engine's event queue; the
// engine never calls back into Dart, so there is no cross-thread callback to get wrong.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'android_capture.dart';
import 'engine.dart';
import 'native_core.dart';
import 'wifi_lock.dart';

const _pollInterval = Duration(milliseconds: 100);

HostEvent? parseHostEvent(String json) {
  final m = jsonDecode(json) as Map<String, dynamic>;
  switch (m['type']) {
    case 'pairing_link':
      return PairingLinkReady(m['link'] as String);
    case 'join_request':
      return JoinRequested(JoinRequest(id: m['id'] as String, name: m['name'] as String, address: m['address'] as String));
    case 'guests':
      return GuestsChanged([for (final g in (m['guests'] as List)) ConnectedGuest(id: g['id'] as String, name: g['name'] as String)]);
    case 'error':
      return HostError(m['message'] as String);
  }
  return null; // unknown event from a newer core: ignore rather than crash
}

GuestStatus? parseGuestStatus(String json) {
  final m = jsonDecode(json) as Map<String, dynamic>;
  final phase = switch (m['phase']) {
    'pairing' => GuestPhase.pairing,
    'awaiting_approval' => GuestPhase.awaitingApproval,
    'connected' => GuestPhase.connected,
    'error' => GuestPhase.error,
    _ => null,
  };
  if (phase == null) return null;
  return GuestStatus(
    phase: phase,
    message: m['message'] as String? ?? '',
    rttUs: (m['rtt_us'] as num?)?.toInt(),
    fillFrames: (m['fill_frames'] as num?)?.toInt(),
    driftPpm: (m['drift_ppm'] as num?)?.toDouble(),
    underruns: (m['underruns'] as num?)?.toInt() ?? 0,
    latePackets: (m['late_packets'] as num?)?.toInt() ?? 0,
    lostPackets: (m['lost_packets'] as num?)?.toInt() ?? 0,
    receivedPackets: (m['received_packets'] as num?)?.toInt() ?? 0,
    maxLateMs: (m['max_late_ms'] as num?)?.toDouble() ?? 0,
    peak: (m['peak'] as num?)?.toDouble() ?? 0,
    outputDevice: m['output_device'] as String?,
    appVolume: (m['app_volume'] as num?)?.toDouble(),
    appMuted: m['app_muted'] as bool?,
  );
}

class FfiHostEngine implements HostEngine {
  FfiHostEngine(this._core, {required this.dataDir});
  final NativeCore _core;
  final String dataDir;
  final _events = StreamController<HostEvent>.broadcast();
  int? _handle;
  Timer? _timer;
  bool _capturing = false; // Android: the capture service is running and pushing into the engine

  @override
  Stream<HostEvent> get events => _events.stream;

  @override
  Future<void> start({required String lanIp, int port = 5005}) async {
    if (_handle != null) return;
    final external = AndroidCapture.isNeeded; // Android cannot loop back system audio; its service pushes PCM
    _handle = _core.hostStart(lanIp, port, dataDir, externalAudio: external); // throws with the engine's message
    _timer = Timer.periodic(_pollInterval, (_) => _drain());
    unawaited(WifiLock.acquire());
    if (external) {
      try {
        await AndroidCapture.start(_core.hostExternalId(_handle!)); // permissions, consent, service
        _capturing = true;
      } on CaptureException {
        await stop(); // nothing can be shared without capture; let the screen show why
        rethrow;
      }
    }
  }

  void _drain() {
    final h = _handle;
    if (h == null) return;
    for (var json = _core.hostPoll(h); json != null; json = _core.hostPoll(h)) {
      final e = parseHostEvent(json);
      if (e != null) _events.add(e);
      if (e is PairingLinkReady && NativeCore.debugEnabled) _dropDebugLink(e.link);
    }
  }

  /// Debug aid (flag file only): lets a developer's script join this host without scanning the QR code.
  void _dropDebugLink(String link) {
    try {
      File('${NativeCore.debugDir}/pairing_link.txt').writeAsStringSync(link);
    } on Object {
      // diagnostics only
    }
  }

  @override
  void respond(String requestId, {required bool allow}) {
    final h = _handle;
    if (h != null) _core.hostRespond(h, requestId, allow);
  }

  @override
  void kick(String guestId) {
    final h = _handle;
    if (h != null) _core.hostKick(h, guestId);
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final h = _handle;
    _handle = null;
    if (_capturing || (h != null && AndroidCapture.isNeeded)) {
      _capturing = false;
      await AndroidCapture.stop(); // stop pushing before the engine goes away
    }
    if (h != null) {
      _core.hostStop(h);
      unawaited(WifiLock.release());
    }
  }
}

class FfiGuestEngine implements GuestEngine {
  FfiGuestEngine(this._core);
  final NativeCore _core;
  final _status = StreamController<GuestStatus>.broadcast();
  int? _handle;
  Timer? _timer;

  @override
  Stream<GuestStatus> get status => _status.stream;

  @override
  Future<void> join(String link, {int audioPort = 0, int delayMs = defaultLatencyMs}) async {
    await leave();
    try {
      _handle = _core.guestJoin(link, audioPort, delayMs);
    } on Object catch (e) {
      _status.add(GuestStatus(phase: GuestPhase.error, message: '$e'));
      return;
    }
    _timer = Timer.periodic(_pollInterval, (_) => _drain());
    unawaited(WifiLock.acquire()); // keep the radio out of power-save for the session (Android)
  }

  void _drain() {
    final g = _handle;
    if (g == null) return;
    for (var json = _core.guestPoll(g); json != null; json = _core.guestPoll(g)) {
      final s = parseGuestStatus(json);
      if (s == null) continue;
      _status.add(s);
      if (s.phase == GuestPhase.error) {
        // The engine's worker has already ended; release the handle so Join can be tried again.
        _release();
        return;
      }
    }
  }

  void _release() {
    _timer?.cancel();
    _timer = null;
    final g = _handle;
    _handle = null;
    if (g != null) {
      _core.guestLeave(g);
      unawaited(WifiLock.release());
    }
  }

  @override
  Future<void> leave() async {
    final wasActive = _handle != null;
    _release();
    if (wasActive) _status.add(const GuestStatus());
  }
}
