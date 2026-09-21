import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xalarm/core/net/url_policy.dart';

void main() {
  group('UrlPolicy.isPrivateAddress', () {
    test('private and loopback ranges', () {
      for (final ip in [
        '127.0.0.1', '10.1.2.3', '172.16.0.1', '172.31.255.255',
        '192.168.1.20', '169.254.1.1', '100.64.0.1', '::1', 'fe80::1',
        'fd12::1', '::ffff:192.168.0.5',
      ]) {
        expect(UrlPolicy.isPrivateAddress(InternetAddress(ip)), isTrue,
            reason: ip);
      }
    });

    test('public addresses', () {
      for (final ip in [
        '8.8.8.8', '172.32.0.1', '100.128.0.1', '2001:db8::1', '1.1.1.1',
      ]) {
        expect(UrlPolicy.isPrivateAddress(InternetAddress(ip)), isFalse,
            reason: ip);
      }
    });
  });

  group('UrlPolicy.checkHttp / checkWebSocket', () {
    test('https and wss are always fine', () {
      expect(UrlPolicy.checkHttp('https://xalarm.example.com'), isNull);
      expect(UrlPolicy.checkWebSocket('wss://xalarm.example.com/sync'), isNull);
    });

    test('cleartext only to local hosts', () {
      expect(UrlPolicy.checkHttp('http://192.168.1.5:49731'), isNull);
      expect(UrlPolicy.checkHttp('http://localhost:8080'), isNull);
      expect(UrlPolicy.checkHttp('http://nas.local'), isNull);
      expect(UrlPolicy.checkWebSocket('ws://10.0.0.2:49732/ws'), isNull);
      expect(UrlPolicy.checkHttp('http://xalarm.example.com'), isNotNull);
      expect(UrlPolicy.checkWebSocket('ws://xalarm.example.com'), isNotNull);
    });

    test('other schemes and junk are refused', () {
      expect(UrlPolicy.checkHttp('ftp://x.example'), isNotNull);
      expect(UrlPolicy.checkHttp('javascript:alert(1)'), isNotNull);
      expect(UrlPolicy.checkHttp(''), isNotNull);
      expect(UrlPolicy.checkWebSocket('https://x.example'), isNotNull);
    });
  });
}
