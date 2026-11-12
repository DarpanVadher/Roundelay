import 'dart:async';
import 'engine.dart';

String _fakeLink(int n) => 'mpsp://pair?h=192.168.1.20:5005&fp=${'ab' * 32}&t=${n.toRadixString(16).padLeft(32, '0')}';

class MockHostEngine implements HostEngine {
  MockHostEngine({this.requestAfter = const Duration(seconds: 3)});
  final Duration requestAfter;
  final _c = StreamController<HostEvent>.broadcast();
  final _guests = <String, ConnectedGuest>{};
  int _n = 0;
  @override Stream<HostEvent> get events => _c.stream;

  void _newRound() {
    _c.add(PairingLinkReady(_fakeLink(++_n)));
    Timer(requestAfter, () => _c.add(JoinRequested(JoinRequest(id: 'r$_n', name: 'Pixel $_n', address: '192.168.1.${30 + _n}'))));
  }

  @override Future<void> start({required String lanIp, int port = 5005}) async => _newRound();
  @override void respond(String requestId, {required bool allow}) {
    if (allow) {
      _guests[requestId] = ConnectedGuest(id: requestId, name: 'Pixel ${requestId.substring(1)}', rttUs: 320);
      _c.add(GuestsChanged(_guests.values.toList()));
    }
    _newRound();
  }
  @override void kick(String id) { _guests.remove(id); _c.add(GuestsChanged(_guests.values.toList())); }
  @override Future<void> stop() async { _guests.clear(); }
}

class MockGuestEngine implements GuestEngine {
  final _c = StreamController<GuestStatus>.broadcast();
  Timer? _t;
  @override Stream<GuestStatus> get status => _c.stream;
  /// The delay the UI asked for in the last [join] (lets tests check the latency slider).
  int? lastDelayMs;
  /// The link the UI passed to the last [join] (lets tests check that Wi-Fi details were stripped).
  String? lastLink;
  @override Future<void> join(String link, {int audioPort = 0, int delayMs = defaultLatencyMs}) async {
    lastDelayMs = delayMs;
    lastLink = link;
    if (!looksLikePairingLink(link)) { _c.add(const GuestStatus(phase: GuestPhase.error, message: 'Not a valid pairing link')); return; }
    _c.add(const GuestStatus(phase: GuestPhase.pairing, message: 'Connecting to host...'));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _c.add(const GuestStatus(phase: GuestPhase.awaitingApproval, message: 'Waiting for the host to approve'));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _c.add(const GuestStatus(
        phase: GuestPhase.connected, message: 'Playing in sync', rttUs: 320, fillFrames: 1920, driftPpm: -12)));
    _c.add(const GuestStatus(phase: GuestPhase.connected, message: 'Playing in sync', rttUs: 320, fillFrames: 1920, driftPpm: 0));
  }
  @override Future<void> leave() async { _t?.cancel(); _c.add(const GuestStatus()); }
}
