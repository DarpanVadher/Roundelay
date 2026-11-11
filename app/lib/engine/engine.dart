// Boundary between the Flutter UI and the audio engine (Rust core). The UI only talks to these
// interfaces; MockEngine backs UI development and tests, FfiEngine (next step) wraps core/.
import 'dart:async';

class JoinRequest {
  const JoinRequest({required this.id, required this.name, required this.address});
  final String id, name, address;
}

class ConnectedGuest {
  const ConnectedGuest({required this.id, required this.name, this.rttUs});
  final String id, name;
  final int? rttUs; // last measured round trip, null until first sync
}

sealed class HostEvent {}
class PairingLinkReady extends HostEvent { PairingLinkReady(this.link); final String link; }
class JoinRequested extends HostEvent { JoinRequested(this.request); final JoinRequest request; }
class GuestsChanged extends HostEvent { GuestsChanged(this.guests); final List<ConnectedGuest> guests; }
class HostError extends HostEvent { HostError(this.message); final String message; }

abstract class HostEngine {
  Stream<HostEvent> get events;
  Future<void> start({required String lanIp, int port = 5005});
  /// Answer a [JoinRequested]; the engine then issues a fresh pairing link for the next guest.
  void respond(String requestId, {required bool allow});
  void kick(String guestId);
  Future<void> stop();
}

enum GuestPhase { idle, pairing, awaitingApproval, connected, error }

class GuestStatus {
  const GuestStatus({this.phase = GuestPhase.idle, this.message = '', this.rttUs, this.fillFrames, this.driftPpm, this.underruns = 0, this.latePackets = 0, this.lostPackets = 0, this.receivedPackets = 0, this.peak = 0, this.maxLateMs = 0, this.outputDevice, this.appVolume, this.appMuted});
  final GuestPhase phase;
  final String message;
  final int? rttUs, fillFrames;
  final double? driftPpm;
  final int underruns, latePackets, lostPackets, receivedPackets;
  final double maxLateMs; // worst packet lateness since the previous status
  final String? outputDevice; // where the audio is playing (desktop); follows Bluetooth/speaker switches
  /// This app's slider (0..1) and mute switch in the OS volume mixer (Windows); null where the OS has none we can read.
  final double? appVolume;
  final bool? appMuted;

  /// The audio is arriving but the operating system's mixer keeps it from being heard.
  bool get mixerSilencesApp => appMuted == true || (appVolume != null && appVolume! < 0.05);
  final double peak; // loudest decoded sample since the previous status, 0..1 (about 0 = the stream is silent)
}

/// Total delay between the host playing a sound and guests playing it. It has to exceed the network's worst
/// delivery jitter or packets arrive after their turn and glitch. Measured on a phone over home Wi-Fi: 80 ms gave
/// 8.7% late packets, 120 ms 0.6%, 140 ms and above none (worst spike 95 ms), so 160 ms leaves a margin.
const int defaultLatencyMs = 160;

abstract class GuestEngine {
  Stream<GuestStatus> get status;
  /// `audioPort` 0 lets the engine pick a free port (so several guests can run on one machine).
  Future<void> join(String link, {int audioPort = 0, int delayMs = defaultLatencyMs});
  Future<void> leave();
}

/// Validates a pairing link the same way the Rust core does (`parse_link`), for early UI feedback.
bool looksLikePairingLink(String s) {
  final u = s.trim();
  if (!u.startsWith('mpsp://pair?')) return false;
  final q = Uri.splitQueryString(u.substring('mpsp://pair?'.length));
  return (q['h'] ?? '').contains(':') && RegExp(r'^[0-9a-f]{64}$').hasMatch(q['fp'] ?? '') && RegExp(r'^[0-9a-f]{32}$').hasMatch(q['t'] ?? '');
}
