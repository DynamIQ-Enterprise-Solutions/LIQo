// Finding the server through the address file (docs/shopper-package-format.md
// §12): read when the app opens, read again when the server can't be reached and
// the call tried once more, the last good address remembered for when the file
// can't be read, and only a plain https://host accepted.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liqo_mobile/core/data/picture_cache.dart';
import 'package:liqo_mobile/core/data/server_address.dart';
import 'package:liqo_mobile/core/data/shopper_api.dart';
import 'package:liqo_mobile/core/storage/store.dart';

const configUrl = 'https://liqo.example.com/config/api.json';
const dirJson = '{"branches":[{"id":"7","name":"North","mallId":"1","mallName":"Mall"}]}';

/// The address file, steerable: what it says, or unreadable.
class FakeFile {
  String? apiBase = 'https://one.example.com';
  bool down = false;
  int reads = 0;
  Future<String> call(Uri url) async {
    reads++;
    expect(url.toString(), configUrl);
    if (down) throw Exception('offline');
    return jsonEncode({'apiBase': apiBase, 'updatedAt': '2026-10-23T18:50:54+08:00'});
  }
}

/// Servers by host: those in [up] answer the directory, the rest can't be reached.
MockClient servers(Set<String> up, List<String> asked, {int? status}) => MockClient((r) async {
      asked.add(r.url.host);
      if (!up.contains(r.url.host)) throw http.ClientException('no such host');
      if (status != null) return http.Response('', status);
      return http.Response(dirJson, 200);
    });

void main() {
  test('the file is read when the app opens; the address is used and remembered', () async {
    final file = FakeFile(), store = MemoryStore(), asked = <String>[];
    final api = HttpShopperApi(ServerAddress.fromFile(configUrl, store, file.call), servers({'one.example.com'}, asked));
    expect((await api.directory()).branches.single.id, '7');
    await api.directory();
    expect(file.reads, 1, reason: 'read once, then kept for the session');
    expect(asked, ['one.example.com', 'one.example.com']);
    expect(store.get(ServerAddress.rememberedKey), 'https://one.example.com');
  });

  test('the server moved: the file is read again and the call tried once more at the new address', () async {
    final file = FakeFile(), asked = <String>[];
    final api = HttpShopperApi(ServerAddress.fromFile(configUrl, MemoryStore(), file.call), servers({'two.example.com'}, asked));
    await api.appConfig().catchError((_) => const AppConfig()); // learns one.example.com, which is gone
    asked.clear();
    file.apiBase = 'https://two.example.com';
    expect((await api.directory()).branches, hasLength(1));
    expect(asked, ['one.example.com', 'two.example.com']);
    expect(file.reads, 3);
  });

  test('the same address after reading again: offline, not tried twice', () async {
    final file = FakeFile(), asked = <String>[];
    final api = HttpShopperApi(ServerAddress.fromFile(configUrl, MemoryStore(), file.call), servers({}, asked));
    await expectLater(api.directory(), throwsA(isA<OfflineException>()));
    expect(asked, ['one.example.com']);
  });

  test("the tunnel's own 'server gone' answers count as unreachable", () async {
    for (final code in [502, 504, 530]) {
      final file = FakeFile(), asked = <String>[];
      final api = HttpShopperApi(ServerAddress.fromFile(configUrl, MemoryStore(), file.call), servers({'one.example.com'}, asked, status: code));
      await expectLater(api.directory(), throwsA(isA<OfflineException>()), reason: '$code');
      expect(file.reads, 2, reason: 'read again after $code');
    }
    final api = HttpShopperApi(ServerAddress.fromFile(configUrl, MemoryStore(), FakeFile().call), servers({'one.example.com'}, [], status: 404));
    await expectLater(api.directory(), throwsA(isA<ServerException>()), reason: 'the server itself answered');
  });

  test("the file can't be read: the remembered address is used; nothing remembered is offline", () async {
    final file = FakeFile()..down = true, asked = <String>[];
    final store = MemoryStore({ServerAddress.rememberedKey: 'https://one.example.com'});
    final api = HttpShopperApi(ServerAddress.fromFile(configUrl, store, file.call), servers({'one.example.com'}, asked));
    expect((await api.directory()).branches, hasLength(1));
    final none = HttpShopperApi(ServerAddress.fromFile(configUrl, MemoryStore(), file.call), servers({'one.example.com'}, asked));
    await expectLater(none.directory(), throwsA(isA<OfflineException>()), reason: 'first launch offline: "Connect once"');
  });

  test('anything but a plain https://host in the file is ignored', () async {
    expect(plainApiBase('https://cook-outsourcing-hold-bacteria.trycloudflare.com'), isNotNull);
    for (final bad in ['http://a.example.com', 'https://a.example.com/', 'https://a.example.com/api', 'https://a.example.com?x=1',
      'https://a.example.com:8443', 'https://u@a.example.com', 'https://a.example.com#x', 'a.example.com', '', 42, null]) {
      expect(plainApiBase(bad), isNull, reason: '$bad');
    }
    final file = FakeFile()..apiBase = 'https://evil.example.com/path';
    final store = MemoryStore({ServerAddress.rememberedKey: 'https://one.example.com'}), asked = <String>[];
    final api = HttpShopperApi(ServerAddress.fromFile(configUrl, store, file.call), servers({'one.example.com'}, asked));
    await api.directory();
    expect(asked, ['one.example.com']);
    expect(store.get(ServerAddress.rememberedKey), 'https://one.example.com');
  });

  test('an address set at build time never reads a file; none at all is offline', () async {
    final asked = <String>[];
    expect((await HttpShopperApi(ServerAddress.fixed('https://one.example.com'), servers({'one.example.com'}, asked)).directory()).branches, hasLength(1));
    await expectLater(HttpShopperApi(ServerAddress.fixed(''), servers({}, asked)).directory(), throwsA(isA<OfflineException>()));
    expect(asked, ['one.example.com']);
  });

  test("the server's pictures are kept by path, so a new address doesn't load them again", () {
    expect(PictureCache.keyOf('https://one.example.com/api/shopper/pictures/ab12.png'), PictureCache.keyOf('https://two.example.com/api/shopper/pictures/ab12.png'));
    expect(PictureCache.keyOf('https://one.example.com/logo.png'), isNot(PictureCache.keyOf('https://two.example.com/logo.png')));
  });
}
