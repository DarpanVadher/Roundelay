import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiphone_player/engine/engine.dart';
import 'package:multiphone_player/engine/mock_engine.dart';
import 'package:multiphone_player/engine/wifi_share.dart';
import 'package:multiphone_player/screens/guest_screen.dart';
import 'package:multiphone_player/screens/host_screen.dart';

final _link = 'mpsp://pair?h=192.168.1.20:5005&fp=${'ab' * 32}&t=${'cd' * 16}';

class _FakeBridge implements WifiBridge {
  _FakeBridge({this.canStart = true, this.canJoin = true, this.joinError});
  final bool canStart, canJoin;
  final String? joinError;
  final joined = <WifiCredentials>[];
  var left = 0, hotspotStopped = 0;
  @override
  bool get canStartHotspot => canStart;
  @override
  bool get canJoinWifi => canJoin;
  @override
  Future<WifiCredentials> startHotspot() async => const WifiCredentials(
    ssid: 'DIRECT-roundelay',
    password: 'abc12345',
    local: true,
  );
  @override
  Future<void> stopHotspot() async => hotspotStopped++;
  @override
  Future<void> joinWifi(WifiCredentials wifi) async {
    if (joinError != null) throw WifiBridgeException(joinError!);
    joined.add(wifi);
  }

  @override
  Future<void> leaveWifi() async => left++;
}

class _MemStore implements WifiStore {
  WifiCredentials? wifi;
  bool include = false;
  @override
  Future<({WifiCredentials? wifi, bool include})> load() async =>
      (wifi: wifi, include: include);
  @override
  Future<void> save({
    required WifiCredentials? wifi,
    required bool include,
  }) async {
    this.wifi = wifi;
    this.include = include;
  }
}

void _phone(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.75;
  addTearDown(t.view.reset);
}

/// The mock host has a pending "join request" timer; run it out so the test ends clean.
Future<void> _drain(WidgetTester t) => t.pump(const Duration(hours: 2));

Future<void> _pumpHost(
  WidgetTester t,
  _FakeBridge bridge,
  _MemStore store,
) async {
  _phone(t);
  await t.pumpWidget(
    MaterialApp(
      home: HostScreen(
        engine: MockHostEngine(requestAfter: const Duration(hours: 1)),
        lanIp: () async => '192.168.1.20',
        wifiBridge: bridge,
        wifiStore: store,
        // The real probe reads network interfaces and waits for a hotspot; the test supplies the address directly.
        hotspotIp: (start) async {
          await start();
          return '192.168.43.1';
        },
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 100));
}

/// What the QR carries is what the copy button copies; read it through the (mocked) clipboard.
Future<String> _qrData(WidgetTester t) async {
  String? copied;
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    },
  );
  addTearDown(
    () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  await t.ensureVisible(find.byKey(const Key('copy-link')));
  await t.tap(find.byKey(const Key('copy-link')));
  await t.pump();
  return copied!;
}

void main() {
  test(
    'Wi-Fi details round-trip through the link, including awkward characters',
    () {
      const wifi = WifiCredentials(
        ssid: 'My Wi-Fi; #1 & co',
        password: 'p&ss=wo rd/é',
      );
      final composed = composeLink(_link, wifi: wifi, hostIp: '192.168.43.1');
      expect(looksLikePairingLink(composed), isTrue);
      expect(composed, contains('h=192.168.43.1:5005'));
      expect(wifiFromLink(composed), wifi);
      expect(
        stripWifi(composed),
        _link.replaceFirst('192.168.1.20', '192.168.43.1'),
      );
    },
  );

  test(
    'open networks carry no password; links without Wi-Fi are unchanged',
    () {
      final open = composeLink(
        _link,
        wifi: const WifiCredentials(ssid: 'Cafe'),
      );
      expect(open, isNot(contains('wp=')));
      expect(wifiFromLink(open)!.isOpen, isTrue);
      expect(composeLink(_link), _link);
      expect(wifiFromLink(_link), isNull);
      expect(stripWifi(_link), _link);
    },
  );

  testWidgets('host: typed Wi-Fi goes into the QR and is remembered', (
    t,
  ) async {
    final store = _MemStore();
    await _pumpHost(t, _FakeBridge(canStart: false), store);
    expect(wifiFromLink(await _qrData(t)), isNull);
    await t.tap(find.byKey(const Key('wifi-switch')));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('wifi-warning')), findsOneWidget);
    expect(
      find.byKey(const Key('start-hotspot')),
      findsNothing,
    ); // this device cannot start a hotspot
    await t.enterText(find.byKey(const Key('wifi-ssid')), 'Home hotspot');
    await t.enterText(find.byKey(const Key('wifi-password')), 'secret 99');
    await t.pump();
    expect(
      wifiFromLink(await _qrData(t)),
      const WifiCredentials(ssid: 'Home hotspot', password: 'secret 99'),
    );
    expect(
      store.wifi,
      const WifiCredentials(ssid: 'Home hotspot', password: 'secret 99'),
    );
    expect(store.include, isTrue);
    await _drain(t);
  });

  testWidgets('host: saved Wi-Fi is filled in next time', (t) async {
    final store = _MemStore()
      ..wifi = const WifiCredentials(ssid: 'Saved', password: 'pw')
      ..include = true;
    await _pumpHost(t, _FakeBridge(canStart: false), store);
    expect(
      wifiFromLink(await _qrData(t)),
      const WifiCredentials(ssid: 'Saved', password: 'pw'),
    );
    await _drain(t);
  });

  testWidgets(
    'host: "Create a hotspot for me" fills the details, points guests at the hotspot address and stops it on leaving',
    (t) async {
      final bridge = _FakeBridge();
      final store = _MemStore();
      await _pumpHost(t, bridge, store);
      await t.tap(find.byKey(const Key('wifi-switch')));
      await t.pump(const Duration(milliseconds: 300));
      await t.ensureVisible(find.byKey(const Key('start-hotspot')));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.byKey(const Key('start-hotspot')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      final link = (await _qrData(t));
      expect(
        wifiFromLink(link),
        const WifiCredentials(ssid: 'DIRECT-roundelay', password: 'abc12345'),
      );
      expect(link, contains('h=192.168.43.1:'));
      expect(store.wifi, isNull); // an app hotspot's name and password change every time, so they are not remembered
      await t.pumpWidget(const SizedBox());
      expect(bridge.hotspotStopped, 1);
      await _drain(t);
    },
  );

  testWidgets(
    'guest: Android joins the hotspot first, then pairs with the Wi-Fi details removed',
    (t) async {
      final bridge = _FakeBridge();
      final engine = MockGuestEngine();
      _phone(t);
      await t.pumpWidget(
        MaterialApp(
          home: GuestScreen(engine: engine, wifiBridge: bridge),
        ),
      );
      final link = composeLink(
        _link,
        wifi: const WifiCredentials(ssid: 'Roundelay-AP', password: 'abc12345'),
      );
      await t.enterText(find.byKey(const Key('link-field')), link);
      await t.pump();
      await t.tap(find.byKey(const Key('join')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(
        bridge.joined.single,
        const WifiCredentials(ssid: 'Roundelay-AP', password: 'abc12345'),
      );
      expect(engine.lastLink, _link);
      await t.pump(const Duration(seconds: 2));
      await t.tap(find.byKey(const Key('leave')));
      await t.pump(const Duration(seconds: 2));
      expect(bridge.left, greaterThan(0));
    },
  );

  testWidgets('guest: a failed Wi-Fi join is explained and nothing is paired', (
    t,
  ) async {
    final bridge = _FakeBridge(joinError: 'Could not join "Roundelay-AP".');
    final engine = MockGuestEngine();
    _phone(t);
    await t.pumpWidget(
      MaterialApp(
        home: GuestScreen(engine: engine, wifiBridge: bridge),
      ),
    );
    await t.enterText(
      find.byKey(const Key('link-field')),
      composeLink(
        _link,
        wifi: const WifiCredentials(ssid: 'Roundelay-AP', password: 'x'),
      ),
    );
    await t.pump();
    await t.tap(find.byKey(const Key('join')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('wifi-error')), findsOneWidget);
    expect(engine.lastLink, isNull);
    await _drain(t);
  });

  testWidgets(
    'guest: where the app cannot join Wi-Fi (Windows) it shows the name and password, then pairs',
    (t) async {
      final bridge = _FakeBridge(canJoin: false);
      final engine = MockGuestEngine();
      _phone(t);
      await t.pumpWidget(
        MaterialApp(
          home: GuestScreen(engine: engine, wifiBridge: bridge),
        ),
      );
      await t.enterText(
        find.byKey(const Key('link-field')),
        composeLink(
          _link,
          wifi: const WifiCredentials(
            ssid: 'Roundelay-AP',
            password: 'abc12345',
          ),
        ),
      );
      await t.pump();
      await t.tap(find.byKey(const Key('join')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('wifi-dialog')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('wifi-dialog')),
          matching: find.textContaining('Roundelay-AP'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('wifi-dialog')),
          matching: find.textContaining('abc12345'),
        ),
        findsOneWidget,
      );
      expect(engine.lastLink, isNull);
      await t.tap(find.byKey(const Key('wifi-continue')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(engine.lastLink, _link);
      expect(bridge.joined, isEmpty);
      await t.pump(const Duration(seconds: 2));
      await t.tap(find.byKey(const Key('leave')));
      await t.pump(const Duration(seconds: 2));
    },
  );
}
