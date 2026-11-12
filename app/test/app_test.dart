import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiphone_player/engine/android_capture.dart';
import 'package:multiphone_player/engine/engine.dart';
import 'package:multiphone_player/engine/mock_engine.dart';
import 'package:multiphone_player/main.dart';

Widget app({Future<String?> Function(BuildContext)? scanQr, GuestEngine? guest}) => MultiPhonePlayerApp(
    hostFactory: () => MockHostEngine(requestAfter: const Duration(milliseconds: 50)),
    guestFactory: () => guest ?? MockGuestEngine(),
    demoMode: true,
    lanIp: () async => '192.168.1.20',
    scanQr: scanQr);

/// A phone-sized window: the default test surface is small enough that lower list rows are never built.
void phoneScreen(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.75;
  addTearDown(t.view.reset);
}

/// Tap a home choice and wait for the route to build (push needs one frame, then the transition).
Future<void> open(WidgetTester t, String key) async {
  await t.tap(find.byKey(Key(key)));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}


class _FailingHost implements HostEngine {
  _FailingHost(this.error);
  final Object error;
  @override
  Stream<HostEvent> get events => const Stream.empty();
  @override
  Future<void> start({required String lanIp, int port = 5005}) async => throw error;
  @override
  void respond(String requestId, {required bool allow}) {}
  @override
  void kick(String guestId) {}
  @override
  Future<void> stop() async {}
}

/// A guest that connects instantly and reports exactly the status the test wants to see.
class _ScriptedGuest implements GuestEngine {
  _ScriptedGuest(this.connected);
  final GuestStatus connected;
  final _c = StreamController<GuestStatus>.broadcast();
  @override
  Stream<GuestStatus> get status => _c.stream;
  @override
  Future<void> join(String link, {int audioPort = 0, int delayMs = defaultLatencyMs}) async => _c.add(connected);
  @override
  Future<void> leave() async => _c.add(const GuestStatus());
}

/// Opens the guest screen, pastes a valid link and joins.
Future<void> joinWith(WidgetTester t, GuestStatus status) async {
  phoneScreen(t);
  await t.pumpWidget(app(guest: _ScriptedGuest(status)));
  await open(t, 'choose-guest');
  await t.enterText(find.byKey(const Key('link-field')), goodLink);
  await t.pump();
  await t.tap(find.byKey(const Key('join')));
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

GuestStatus connectedWith({double? volume, bool? muted}) =>
    GuestStatus(phase: GuestPhase.connected, message: 'Playing in sync', appVolume: volume, appMuted: muted);

final goodLink = 'mpsp://pair?h=1.2.3.4:5005&fp=${'ab' * 32}&t=${'cd' * 16}';

void main() {
  test('link validation mirrors the core parser', () {
    expect(looksLikePairingLink(goodLink), isTrue);
    expect(looksLikePairingLink('http://x'), isFalse);
    expect(looksLikePairingLink('mpsp://pair?h=1.2.3.4:5005&fp=zz&t=${'cd' * 16}'), isFalse);
    expect(looksLikePairingLink('mpsp://pair?h=nohostport&fp=${'ab' * 32}&t=${'cd' * 16}'), isFalse);
  });

  testWidgets('host: QR shown, join request approved, guest listed, new QR issued', (t) async {
    phoneScreen(t);
    await t.pumpWidget(app());
    await open(t, 'choose-host');
    expect(find.byKey(const Key('pairing-qr')), findsOneWidget);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('join-request')), findsOneWidget);
    await t.tap(find.byKey(const Key('allow')));
    await t.pump();
    expect(find.text('Connected devices (1)'), findsOneWidget);
    expect(find.byKey(const Key('join-request')), findsNothing);
    expect(find.byKey(const Key('pairing-qr')), findsOneWidget); // fresh single-use QR
    await t.pump(const Duration(milliseconds: 100)); // drain the mock's pending timer
  });

  testWidgets('host: denied guest is not listed', (t) async {
    phoneScreen(t);
    await t.pumpWidget(app());
    await open(t, 'choose-host');
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.byKey(const Key('deny')));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Connected devices (0)'), findsOneWidget);
  });

  testWidgets('guest: join disabled until the link is valid, then connects', (t) async {
    await t.pumpWidget(app());
    await open(t, 'choose-guest');
    FilledButton join() => t.widget<FilledButton>(find.byKey(const Key('join')));
    expect(join().onPressed, isNull);
    await t.enterText(find.byKey(const Key('link-field')), 'garbage');
    await t.pump();
    expect(join().onPressed, isNull);
    expect(find.textContaining("doesn't look like"), findsOneWidget);
    await t.enterText(find.byKey(const Key('link-field')), goodLink);
    await t.pump();
    await t.tap(find.byKey(const Key('join')));
    await t.pump(const Duration(seconds: 2));
    expect(find.text('Playing in sync'), findsOneWidget);
    expect(find.byKey(const Key('leave')), findsOneWidget);
    await t.tap(find.byKey(const Key('leave')));
    await t.pump();
  });

  testWidgets('guest: scanning a valid QR fills the link and joins straight away', (t) async {
    await t.pumpWidget(app(scanQr: (_) async => goodLink));
    await open(t, 'choose-guest');
    expect(find.byKey(const Key('scan')), findsOneWidget);
    await t.tap(find.byKey(const Key('scan')));
    await t.pump();
    await t.pump(const Duration(seconds: 2));
    expect(find.text('Playing in sync'), findsOneWidget);
    expect(find.byKey(const Key('leave')), findsOneWidget);
    await t.tap(find.byKey(const Key('leave')));
    await t.pump();
  });

  testWidgets('guest: backing out of the scanner changes nothing', (t) async {
    await t.pumpWidget(app(scanQr: (_) async => null));
    await open(t, 'choose-guest');
    await t.tap(find.byKey(const Key('scan')));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('status')), findsNothing);
    expect(t.widget<FilledButton>(find.byKey(const Key('join'))).onPressed, isNull);
  });

  testWidgets('guest: no scan button on a device without a camera (desktop)', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await t.pumpWidget(app());
      await open(t, 'choose-guest');
      expect(find.byKey(const Key('scan')), findsNothing);
      expect(find.byKey(const Key('link-field')), findsOneWidget); // pasting still works
    } finally {
      debugDefaultTargetPlatformOverride = null; // the framework checks this before tearDown callbacks run
    }
  });

  testWidgets('guest: latency defaults to 160 ms and the chosen value reaches the engine', (t) async {
    final engine = MockGuestEngine();
    await t.pumpWidget(app(guest: engine));
    await open(t, 'choose-guest');
    expect(find.text('Latency: 160 ms'), findsOneWidget);
    t.widget<Slider>(find.byKey(const Key('latency'))).onChanged!(250);
    await t.pump();
    expect(find.text('Latency: 250 ms'), findsOneWidget);
    await t.enterText(find.byKey(const Key('link-field')), goodLink);
    await t.pump();
    await t.tap(find.byKey(const Key('join')));
    await t.pump(const Duration(seconds: 2));
    expect(engine.lastDelayMs, 250);
    expect(find.byKey(const Key('latency')), findsNothing); // fixed while connected
    await t.tap(find.byKey(const Key('leave')));
    await t.pump();
  });

  testWidgets('guest: scanning joins with the default latency', (t) async {
    final engine = MockGuestEngine();
    await t.pumpWidget(app(scanQr: (_) async => goodLink, guest: engine));
    await open(t, 'choose-guest');
    await t.tap(find.byKey(const Key('scan')));
    await t.pump();
    await t.pump(const Duration(seconds: 2));
    expect(engine.lastDelayMs, defaultLatencyMs);
    await t.tap(find.byKey(const Key('leave')));
    await t.pump();
  });

  test('capture errors become readable messages', () {
    expect(captureErrorMessage('denied', null), contains('declined'));
    expect(captureErrorMessage('denied_mic', null), contains('no microphone is used'));
    expect(captureErrorMessage('unsupported', null), contains('Android 10'));
    expect(captureErrorMessage('capture_failed', 'boom'), 'Could not start audio capture: boom');
    expect(captureErrorMessage('capture_failed', null), 'Could not start audio capture.');
    expect(captureErrorMessage('something_new', '  '.trim()), 'Could not start audio capture.');
  });

  testWidgets('host: a declined capture permission is explained, not hidden', (t) async {
    await t.pumpWidget(MultiPhonePlayerApp(
      hostFactory: () => _FailingHost(CaptureException(captureErrorMessage('denied', null))),
      guestFactory: MockGuestEngine.new,
      lanIp: () async => '192.168.1.20',
    ));
    await open(t, 'choose-host');
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Screen-capture permission was declined'), findsOneWidget);
    expect(find.byKey(const Key('pairing-qr')), findsNothing);
  });

  testWidgets('host: Android shows the capture hint', (t) async {
    await t.pumpWidget(app());
    await open(t, 'choose-host');
    expect(find.textContaining('Apps that block audio capture'), findsOneWidget); // tests default to android
  });

  testWidgets('guest: a muted app gets a plain warning instead of a silent "Playing in sync"', (t) async {
    await joinWith(t, connectedWith(volume: 1.0, muted: true));
    expect(find.byKey(const Key('mixer-warning')), findsOneWidget);
    expect(find.textContaining('this app is muted in Windows'), findsOneWidget);
    expect(find.text('Playing in sync'), findsOneWidget, reason: 'the normal status is still shown beneath it');
    if (Platform.isWindows) expect(find.byKey(const Key('open-mixer')), findsOneWidget);
  });

  testWidgets('guest: an app turned almost all the way down says how far', (t) async {
    await joinWith(t, connectedWith(volume: 0.03, muted: false));
    expect(find.byKey(const Key('mixer-warning')), findsOneWidget);
    expect(find.textContaining('turned down to 3% in Windows'), findsOneWidget);
  });

  testWidgets('guest: no warning at normal volume, or where the OS gives no mixer state', (t) async {
    await joinWith(t, connectedWith(volume: 1.0, muted: false));
    expect(find.byKey(const Key('mixer-warning')), findsNothing);
    expect(find.text('Playing in sync'), findsOneWidget);
  });

  testWidgets('guest: unknown mixer state (Android, older core) shows no warning', (t) async {
    await joinWith(t, connectedWith());
    expect(find.byKey(const Key('mixer-warning')), findsNothing);
  });

  testWidgets('guest: the warning disappears once the app is unmuted', (t) async {
    final engine = _ScriptedGuest(connectedWith(volume: 1.0, muted: true));
    phoneScreen(t);
    await t.pumpWidget(app(guest: engine));
    await open(t, 'choose-guest');
    await t.enterText(find.byKey(const Key('link-field')), goodLink);
    await t.pump();
    await t.tap(find.byKey(const Key('join')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('mixer-warning')), findsOneWidget);
    engine._c.add(connectedWith(volume: 1.0, muted: false)); // the person fixed it in the Windows mixer
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('mixer-warning')), findsNothing);
  });

  testWidgets('legal: pages open from home and show their text, including the data table', (t) async {
    phoneScreen(t);
    await t.pumpWidget(app());
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.byKey(const Key('open-legal')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Privacy Policy'), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const Key('legal-data-retention')), 200, scrollable: find.byType(Scrollable).last);
    await t.tap(find.byKey(const Key('legal-data-retention')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Data Retention'), findsWidgets);
    expect(find.textContaining('retain no user data'), findsOneWidget);
    final url = find.textContaining('https://darpanvadher.github.io/Roundelay/legal/data-retention.html');
    await t.scrollUntilVisible(url, 300, scrollable: find.byType(Scrollable).last);
    expect(url, findsOneWidget);
  });
}
