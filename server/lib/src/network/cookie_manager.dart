import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../core/database.dart';
import '../core/log.dart';

class ServerCookieManager extends Interceptor {
  static const String _configKey = 'eh_cookies';

  List<Cookie> cookies = [Cookie('nw', '1'), Cookie('datatags', '1')];

  static const Set<String> _ehHosts = {
    'e-hentai.org',
    'exhentai.org',
    'forums.e-hentai.org',
    'upld.e-hentai.org',
    'api.e-hentai.org',
  };

  static const Map<String, List<String>> host2IPs = {
    'e-hentai.org': ['172.66.132.196', '172.66.140.62'],
    'exhentai.org': [
      '178.175.128.251', '178.175.128.252', '178.175.128.253', '178.175.128.254',
      '178.175.129.251', '178.175.129.252', '178.175.129.253', '178.175.129.254',
      '178.175.132.19', '178.175.132.20', '178.175.132.21', '178.175.132.22',
    ],
    'upld.e-hentai.org': ['95.211.208.236', '89.149.221.236'],
    'api.e-hentai.org': ['37.48.92.161', '212.7.202.51', '5.79.104.110', '37.48.81.204', '212.7.200.104'],
    'forums.e-hentai.org': ['172.66.132.196', '172.66.140.62'],
  };

  Set<String> get allHostAndIPs => _ehHosts.union(host2IPs.values.expand((e) => e).toSet());

  bool isEHHost(String host) => allHostAndIPs.contains(host);

  /// EH session cookies (igneous, ipb_*, etc.) must be sent to gallery HTML hosts and to
  /// image CDNs — same as a real browser. [isEHHost] is still used for merging Set-Cookie.
  bool shouldAttachEhSessionCookies(String host) {
    final h = host.toLowerCase();
    if (isEHHost(h)) return true;
    if (h == 'ehgt.org' || h.endsWith('.ehgt.org')) return true;
    if (h.endsWith('.hath.network')) return true;
    if (h.endsWith('.e-hentai.org') || h.endsWith('.exhentai.org')) return true;
    return false;
  }

  Future<void> init() async {
    final stored = db.readConfig(_configKey);
    if (stored != null) {
      try {
        final list = jsonDecode(stored) as List;
        cookies.addAll(list.cast<String>().map(Cookie.fromSetCookieValue));
      } catch (e) {
        log.warning('Failed to parse stored cookies', e);
      }
    }
  }

  Future<void> storeCookies(List<Cookie> newCookies) async {
    newCookies.removeWhere((c) => c.name == '__utmp');
    newCookies.removeWhere((c) => c.name == 'igneous' && c.value == 'mystery');

    cookies.removeWhere((c) => newCookies.any((nc) => nc.name == c.name));
    cookies.addAll(newCookies);

    final toStore = cookies.where((c) => c.name != 'nw' && c.name != 'datatags').toList();
    db.writeConfig(_configKey, jsonEncode(toStore.map((c) => c.toString()).toList()));
  }

  Future<void> removeAllCookies() async {
    db.deleteConfig(_configKey);
    cookies = [Cookie('nw', '1'), Cookie('datatags', '1')];
  }

  void removeCookies(List<String> names) {
    cookies.removeWhere((c) => names.contains(c.name));
    final toStore = cookies.where((c) => c.name != 'nw' && c.name != 'datatags').toList();
    db.writeConfig(_configKey, jsonEncode(toStore.map((c) => c.toString()).toList()));
  }

  String cookieHeader() {
    return cookies.map((c) => '${c.name}=${c.value}').join('; ');
  }

  bool get hasLoggedIn {
    final memberId = cookies.where((c) => c.name == 'ipb_member_id').firstOrNull;
    final passHash = cookies.where((c) => c.name == 'ipb_pass_hash').firstOrNull;
    return memberId != null && passHash != null && memberId.value != '0' && passHash.value != '0';
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (shouldAttachEhSessionCookies(options.uri.host)) {
      options.headers[HttpHeaders.cookieHeader] = cookieHeader();
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final setCookieHeaders = response.headers[HttpHeaders.setCookieHeader];
    if (setCookieHeaders != null && isEHHost(response.requestOptions.uri.host)) {
      final newCookies = setCookieHeaders
          .map(Cookie.fromSetCookieValue)
          .map((c) => Cookie(c.name, c.value))
          .toList();
      storeCookies(newCookies);
    }
    handler.next(response);
  }
}
