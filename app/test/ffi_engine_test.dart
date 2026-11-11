// Drives the real Rust core through dart:ffi. The integration group needs the built library:
//   MPSP_FFI_PATH=<path to mpsp_ffi.dll> flutter test test/ffi_engine_test.dart
// Without it that group is skipped (the parsing tests always run).
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiphone_player/engine/engine.dart';
import 'package:multiphone_player/engine/ffi_engine.dart';
import 'package:multiphone_player/engine/native_core.dart';
import 'package:multiphone_player/engine/platform_info.dart';

/// Polls until [cond] holds (real time: these tests use real sockets and threads).
Future<void> waitFor(bool Function() cond, String what, {int seconds = 15}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  group('event parsing', () {
    test('host events', () {
      expect((parseHostEvent('{"type":"pairing_link","link":"mpsp://x"}') as PairingLinkReady).link, 'mpsp://x');
      final j = parseHostEvent('{"type":"join_request","id":"g1","name":"Pixel","address":"1.2.3.4"}') as JoinRequested;
      expect((j.request.id, j.request.name, j.request.address), ('g1', 'Pixel', '1.2.3.4'));
      final g = parseHostEvent('{"type":"guests","guests":[{"id":"g1","name":"A"},{"id":"g2","name":"B"}]}') as GuestsChanged;
      expect(g.guests.map((e) => e.name), ['A', 'B']);
      expect((parseHostEvent('{"type":"error","message":"boom"}') as HostError).message, 'boom');
      expect(parseHostEvent('{"type":"from_the_future"}'), isNull);
    });

    test('guest status', () {
      final s = parseGuestStatus('{"phase":"connected","message":"Playing in sync","rtt_us":312,"fill_frames":1920,"drift_ppm":-4.5,"underruns":2}')!;
      expect((s.phase, s.rttUs, s.fillFrames, s.driftPpm, s.underruns), (GuestPhase.connected, 312, 1920, -4.5, 2));
      final p = parseGuestStatus('{"phase":"awaiting_approval","message":"wait","rtt_us":null,"fill_frames":null,"drift_ppm":null,"underruns":0}')!;
      expect((p.phase, p.rttUs), (GuestPhase.awaitingApproval, null));
      expect(parseGuestStatus('{"phase":"mystery","message":""}'), isNull);
    });

    test('mixer state: muted or near-zero means the app is silenced, normal or unknown does not', () {
      GuestStatus parse(String extra) => parseGuestStatus('{"phase":"connected","message":"ok"$extra}')!;
      expect(parse(',"app_volume":1.0,"app_muted":true').mixerSilencesApp, isTrue);
      expect(parse(',"app_volume":0.0,"app_muted":false').mixerSilencesApp, isTrue);
      expect(parse(',"app_volume":0.04,"app_muted":false').mixerSilencesApp, isTrue);
      expect(parse(',"app_volume":0.05,"app_muted":false').mixerSilencesApp, isFalse);
      expect(parse(',"app_volume":1.0,"app_muted":false').mixerSilencesApp, isFalse);
      expect(parse(',"app_volume":null,"app_muted":null').mixerSilencesApp, isFalse, reason: 'unknown (non-Windows) is not a warning');
      expect(parse('').mixerSilencesApp, isFalse, reason: 'an older core without the fields');
      final s = parse(',"app_volume":0.08,"app_muted":false');
      expect((s.appVolume, s.appMuted), (0.08, false));
    });

    test('LAN address choice prefers private ranges and skips loopback/link-local', () {
      expect(pickLanIp(['169.254.3.4', '127.0.0.1', '10.0.0.7', '192.168.1.20']), '192.168.1.20');
      expect(pickLanIp(['172.20.1.1', '10.1.1.1']), '10.1.1.1');
      expect(pickLanIp(['172.20.1.1', '8.8.8.8']), '172.20.1.1');
      expect(pickLanIp(['8.8.8.8']), '8.8.8.8');
      expect(pickLanIp(['127.0.0.1', '169.254.1.1']), isNull);
    });
  });

  final core = NativeCore.tryLoad();
  group('real core over FFI', skip: core == null ? 'set MPSP_FFI_PATH to the built mpsp_ffi library' : false, () {
    late Directory tmp;
    late FfiHostEngine host;
    late FfiGuestEngine guest;
    final hostEvents = <HostEvent>[];
    final guestStatuses = <GuestStatus>[];

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('mpsp-ffi-test');
      hostEvents.clear();
      guestStatuses.clear();
      host = FfiHostEngine(core!, dataDir: tmp.path)..events.listen(hostEvents.add);
      guest = FfiGuestEngine(core)..status.listen(guestStatuses.add);
      await host.start(lanIp: '127.0.0.1', port: 0);
    });

    tearDown(() async {
      await guest.leave();
      await host.stop();
      await Future<void>.delayed(const Duration(milliseconds: 700)); // let the native shutdown thread finish
      try { await tmp.delete(recursive: true); } on Object { /* host key file may still be closing */ }
    });

    String latestLink() => hostEvents.whereType<PairingLinkReady>().last.link;

    test('pair, approve, sync, then kick', () async {
      await waitFor(() => hostEvents.whereType<PairingLinkReady>().isNotEmpty, 'pairing link');
      await guest.join(latestLink());
      await waitFor(() => hostEvents.whereType<JoinRequested>().isNotEmpty, 'join request');
      final req = hostEvents.whereType<JoinRequested>().first.request;
      expect(req.address, '127.0.0.1');
      host.respond(req.id, allow: true);

      await waitFor(() => guestStatuses.any((s) => s.phase == GuestPhase.connected), 'guest connected');
      final connected = guestStatuses.lastWhere((s) => s.phase == GuestPhase.connected);
      expect(connected.rttUs, isNotNull);
      expect(connected.rttUs!, inInclusiveRange(0, 50000));
      await waitFor(() => hostEvents.whereType<GuestsChanged>().any((e) => e.guests.length == 1), 'host sees guest');

      host.kick(req.id);
      await waitFor(() => hostEvents.whereType<GuestsChanged>().last.guests.isEmpty, 'host drops guest');
      await waitFor(() => guestStatuses.any((s) => s.phase == GuestPhase.error && s.message.contains('Lost connection')), 'guest notices kick');
    });

    test('a denied guest gets a clear message and can retry with the new link', () async {
      await waitFor(() => hostEvents.whereType<PairingLinkReady>().isNotEmpty, 'pairing link');
      await guest.join(latestLink());
      await waitFor(() => hostEvents.whereType<JoinRequested>().isNotEmpty, 'join request');
      host.respond(hostEvents.whereType<JoinRequested>().first.request.id, allow: false);
      await waitFor(() => guestStatuses.any((s) => s.phase == GuestPhase.error), 'denial');
      expect(guestStatuses.last.message, contains('did not allow'));

      // The denied attempt consumed its single-use link; the host issues a fresh one.
      await waitFor(() => hostEvents.whereType<PairingLinkReady>().length >= 2, 'fresh link');
      guestStatuses.clear();
      await guest.join(latestLink());
      await waitFor(() => hostEvents.whereType<JoinRequested>().length >= 2, 'second join request');
      host.respond(hostEvents.whereType<JoinRequested>().last.request.id, allow: true);
      await waitFor(() => guestStatuses.any((s) => s.phase == GuestPhase.connected), 'connected after retry');
    });

    test('garbage link yields an error status instead of throwing', () async {
      await guest.join('not a link');
      await waitFor(() => guestStatuses.any((s) => s.phase == GuestPhase.error), 'error status');
    });
  });
}
