import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../core/database.dart';
import '../core/log.dart';

const _archiveBotConfigKey = 'archiveBotSetting';
const _defaultEhArBotServerAddress = 'https://eh-arc-api.mhdy.icu';
const _defaultArchiveAtHomeServerAddress = 'https://api.archive-at-home.org';
const _archiveAtHomeXClient = 'app/jhentai';

String? _envValue(String name) {
  final env = Platform.environment;
  return env[name] ?? env[name.toLowerCase()];
}

bool _noProxyMatches(Uri uri, String? rawNoProxy) {
  if (rawNoProxy == null || rawNoProxy.trim().isEmpty) return false;
  final host = uri.host.toLowerCase();
  final hostWithPort = uri.hasPort ? '$host:${uri.port}' : host;
  for (final rawToken in rawNoProxy.split(',')) {
    final token = rawToken.trim().toLowerCase();
    if (token.isEmpty) continue;
    if (token == '*' || token == host || token == hostWithPort) return true;
    if (token.startsWith('*.') && host.endsWith(token.substring(1))) {
      return true;
    }
    if (token.startsWith('.') && host.endsWith(token)) return true;
  }
  return false;
}

({String host, int port, String? username, String? password})?
    _proxyConfigFromUrl(String? rawProxy) {
  if (rawProxy == null || rawProxy.trim().isEmpty) return null;
  final value = rawProxy.trim();
  final uri = Uri.tryParse(value.contains('://') ? value : 'http://$value');
  if (uri == null || uri.host.isEmpty) return null;
  final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
  final userInfo = uri.userInfo;
  String? username;
  String? password;
  if (userInfo.isNotEmpty) {
    final separator = userInfo.indexOf(':');
    if (separator >= 0) {
      username = Uri.decodeComponent(userInfo.substring(0, separator));
      password = Uri.decodeComponent(userInfo.substring(separator + 1));
    } else {
      username = Uri.decodeComponent(userInfo);
      password = '';
    }
    if (username.isEmpty) {
      username = null;
      password = null;
    }
  }
  return (host: uri.host, port: port, username: username, password: password);
}

String? _proxyDirectiveFromUrl(String? rawProxy) {
  final config = _proxyConfigFromUrl(rawProxy);
  return config == null ? null : 'PROXY ${config.host}:${config.port}';
}

HttpClientBasicCredentials? _proxyCredentialsFor(String host, int port) {
  for (final name in const ['HTTPS_PROXY', 'HTTP_PROXY']) {
    final config = _proxyConfigFromUrl(_envValue(name));
    if (config == null || config.host != host || config.port != port) {
      continue;
    }
    final username = config.username;
    if (username == null || username.isEmpty) continue;
    return HttpClientBasicCredentials(username, config.password ?? '');
  }
  return null;
}

String _findProxyForRequest(Uri uri) {
  if (_noProxyMatches(uri, _envValue('NO_PROXY'))) {
    return 'DIRECT';
  }
  final proxy = uri.scheme == 'https'
      ? (_envValue('HTTPS_PROXY') ?? _envValue('HTTP_PROXY'))
      : (_envValue('HTTP_PROXY') ?? _envValue('HTTPS_PROXY'));
  return _proxyDirectiveFromUrl(proxy) ?? 'DIRECT';
}

HttpClient _createProxyAwareHttpClient() {
  final client = HttpClient();
  client.findProxy = _findProxyForRequest;
  client.authenticateProxy = (host, port, scheme, realm) {
    final credentials = _proxyCredentialsFor(host, port);
    if (credentials == null) {
      return Future.value(false);
    }
    client.addProxyCredentials(host, port, realm ?? '', credentials);
    return Future.value(true);
  };
  return client;
}

enum ArchiveBotType {
  ehArBot(0, 'ehArBot', _defaultEhArBotServerAddress),
  archiveAtHome(1, 'archiveAtHome', _defaultArchiveAtHomeServerAddress);

  final int code;
  final String wireName;
  final String defaultServerAddress;

  const ArchiveBotType(
    this.code,
    this.wireName,
    this.defaultServerAddress,
  );

  static ArchiveBotType fromValue(Object? value) {
    if (value is num) {
      return ArchiveBotType.values.firstWhere(
        (type) => type.code == value.toInt(),
        orElse: () => ArchiveBotType.archiveAtHome,
      );
    }
    final text = value?.toString().trim().toLowerCase() ?? '';
    return switch (text) {
      '0' || 'eharbot' || 'eh-arbot' || 'eh_arbot' => ArchiveBotType.ehArBot,
      '1' ||
      'archiveathome' ||
      'archive-at-home' ||
      'archive_at_home' =>
        ArchiveBotType.archiveAtHome,
      _ => ArchiveBotType.archiveAtHome,
    };
  }
}

class ArchiveBotException implements Exception {
  const ArchiveBotException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ArchiveBotSettings {
  ArchiveBotSettings({
    required this.type,
    required this.apiAddress,
    required this.apiKey,
  });

  final ArchiveBotType type;
  final String apiAddress;
  final String? apiKey;

  bool get isConfigured =>
      apiAddress.trim().isNotEmpty && (apiKey?.trim().isNotEmpty ?? false);

  Map<String, dynamic> toStoredJson() => {
        'botType': type.code,
        'apiAddress': apiAddress.trim().isEmpty
            ? type.defaultServerAddress
            : apiAddress.trim(),
        'apiKey': apiKey,
      };

  Map<String, dynamic> toPublicJson() => {
        'type': type.wireName,
        'botType': type.code,
        'typeLabel': type == ArchiveBotType.archiveAtHome
            ? 'Archive-at-Home'
            : 'EH-ArBot',
        'apiAddress': apiAddress,
        'apiKeyConfigured': apiKey?.trim().isNotEmpty == true,
        'configured': isConfigured,
        'protocols': [
          {
            'type': ArchiveBotType.archiveAtHome.wireName,
            'botType': ArchiveBotType.archiveAtHome.code,
            'label': 'Archive-at-Home',
            'defaultApiAddress':
                ArchiveBotType.archiveAtHome.defaultServerAddress,
          },
          {
            'type': ArchiveBotType.ehArBot.wireName,
            'botType': ArchiveBotType.ehArBot.code,
            'label': 'EH-ArBot',
            'defaultApiAddress': ArchiveBotType.ehArBot.defaultServerAddress,
          },
        ],
      };
}

class ArchiveBotService {
  late final Dio _dio;

  Future<void> init() async {
    _dio = Dio(BaseOptions(
      connectTimeout: Duration(
          milliseconds:
              int.tryParse(db.readConfig('web_connect_timeout') ?? '') ?? 6000),
      receiveTimeout: Duration(
          milliseconds:
              int.tryParse(db.readConfig('web_receive_timeout') ?? '') ?? 6000),
    ));
    _dio.httpClientAdapter =
        IOHttpClientAdapter(createHttpClient: _createProxyAwareHttpClient);
    log.info('Archive Bot service initialized');
  }

  ArchiveBotSettings settings() {
    final raw = db.readConfig(_archiveBotConfigKey);
    if (raw == null || raw.trim().isEmpty) {
      return ArchiveBotSettings(
        type: ArchiveBotType.archiveAtHome,
        apiAddress: ArchiveBotType.archiveAtHome.defaultServerAddress,
        apiKey: null,
      );
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('Archive Bot setting is not a JSON object');
      }
      final type =
          ArchiveBotType.fromValue(decoded['botType'] ?? decoded['type']);
      final address = decoded['apiAddress']?.toString().trim();
      return ArchiveBotSettings(
        type: type,
        apiAddress: address == null || address.isEmpty
            ? type.defaultServerAddress
            : address,
        apiKey: decoded['apiKey']?.toString(),
      );
    } catch (e) {
      log.warning('Invalid Archive Bot setting ignored: $e');
      return ArchiveBotSettings(
        type: ArchiveBotType.archiveAtHome,
        apiAddress: ArchiveBotType.archiveAtHome.defaultServerAddress,
        apiKey: null,
      );
    }
  }

  ArchiveBotSettings saveSettings(Map<String, dynamic> body) {
    final current = settings();
    final type = ArchiveBotType.fromValue(
      body.containsKey('botType')
          ? body['botType']
          : body['type'] ?? current.type.wireName,
    );
    final rawAddress = body.containsKey('apiAddress')
        ? body['apiAddress']?.toString().trim()
        : current.apiAddress;
    final apiAddress = rawAddress == null || rawAddress.isEmpty
        ? type.defaultServerAddress
        : rawAddress;
    String? apiKey = current.apiKey;
    if (body['clearApiKey'] == true) {
      apiKey = null;
    } else if (body.containsKey('apiKey')) {
      final rawKey = body['apiKey']?.toString().trim();
      apiKey = rawKey == null || rawKey.isEmpty ? null : rawKey;
    }
    final next = ArchiveBotSettings(
      type: type,
      apiAddress: apiAddress,
      apiKey: apiKey,
    );
    db.writeConfig(_archiveBotConfigKey, jsonEncode(next.toStoredJson()));
    return next;
  }

  Future<Map<String, dynamic>> requestBalance() async {
    final settings = _requireConfiguredSettings();
    final response = await _requestBalance(settings);
    return {
      'success': response.isSuccess,
      'settings': settings.toPublicJson(),
      'response': response.toJson(),
      if (response.data['current_GP'] != null)
        'balance': response.data['current_GP'],
      if (response.data['balance'] != null) 'balance': response.data['balance'],
    };
  }

  Future<Map<String, dynamic>> requestCheckIn() async {
    final settings = _requireConfiguredSettings();
    final response = await _requestCheckIn(settings);
    return {
      'success': response.isSuccess,
      'settings': settings.toPublicJson(),
      'response': response.toJson(),
    };
  }

  Future<Map<String, dynamic>> requestResolve({
    required int gid,
    required String token,
    bool reParse = true,
    CancelToken? cancelToken,
  }) async {
    final settings = _requireConfiguredSettings();
    final response = await _requestResolve(
      settings,
      gid: gid,
      token: token,
      reParse: reParse,
      cancelToken: cancelToken,
    );
    final archiveUrl = response.data['archive_url']?.toString() ?? '';
    return {
      'success': response.isSuccess && archiveUrl.isNotEmpty,
      'settings': settings.toPublicJson(),
      'response': response.toJson(),
      'archiveUrl': archiveUrl,
    };
  }

  Future<String> resolveArchiveUrl({
    required int gid,
    required String token,
    bool reParse = true,
    CancelToken? cancelToken,
  }) async {
    final result = await requestResolve(
      gid: gid,
      token: token,
      reParse: reParse,
      cancelToken: cancelToken,
    );
    if (result['success'] != true) {
      final response = result['response'];
      final message = response is Map
          ? response['message']?.toString()
          : result['error']?.toString();
      throw ArchiveBotException(message == null || message.isEmpty
          ? 'Archive Bot failed to resolve archive URL'
          : message);
    }
    return result['archiveUrl'].toString();
  }

  ArchiveBotSettings _requireConfiguredSettings() {
    final value = settings();
    if (!value.isConfigured) {
      throw const ArchiveBotException(
        'Archive Bot is not configured. Set API address and API key first.',
      );
    }
    return value;
  }

  Future<_ArchiveBotResponse> _requestBalance(ArchiveBotSettings settings) {
    return switch (settings.type) {
      ArchiveBotType.ehArBot => _postEhArBot(
          settings,
          '/balance',
          {'apikey': settings.apiKey},
        ),
      ArchiveBotType.archiveAtHome => _requestArchiveAtHome(
          settings,
          'GET',
          '/api/v1/me/balance',
        ),
    };
  }

  Future<_ArchiveBotResponse> _requestCheckIn(ArchiveBotSettings settings) {
    return switch (settings.type) {
      ArchiveBotType.ehArBot => _postEhArBot(
          settings,
          '/checkin',
          {'apikey': settings.apiKey},
        ),
      ArchiveBotType.archiveAtHome => _requestArchiveAtHome(
          settings,
          'POST',
          '/api/v1/me/checkin',
        ),
    };
  }

  Future<_ArchiveBotResponse> _requestResolve(
    ArchiveBotSettings settings, {
    required int gid,
    required String token,
    required bool reParse,
    CancelToken? cancelToken,
  }) {
    return switch (settings.type) {
      ArchiveBotType.ehArBot => _postEhArBot(
          settings,
          '/resolve',
          {
            'apikey': settings.apiKey,
            'gid': gid,
            'token': token,
            'force_resolve': reParse,
          },
          cancelToken: cancelToken,
        ),
      ArchiveBotType.archiveAtHome => _requestArchiveAtHome(
          settings,
          'POST',
          '/api/v1/parse',
          data: {
            'gallery_id': gid.toString(),
            'gallery_key': token,
            'force': reParse,
          },
          cancelToken: cancelToken,
          extraHeaders: {'X-Client': _archiveAtHomeXClient},
        ),
    };
  }

  Future<_ArchiveBotResponse> _postEhArBot(
    ArchiveBotSettings settings,
    String path,
    Map<String, dynamic> data, {
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.post(
      _joinUrl(settings.apiAddress, path),
      data: data,
      options: Options(
        contentType: Headers.jsonContentType,
        validateStatus: (status) => true,
      ),
      cancelToken: cancelToken,
    );
    return _normalizeWrappedResponse(response);
  }

  Future<_ArchiveBotResponse> _requestArchiveAtHome(
    ArchiveBotSettings settings,
    String method,
    String path, {
    Map<String, dynamic>? data,
    CancelToken? cancelToken,
    Map<String, dynamic>? extraHeaders,
  }) async {
    final response = await _dio.request(
      _joinUrl(settings.apiAddress, path),
      data: data,
      options: Options(
        method: method,
        contentType: Headers.jsonContentType,
        validateStatus: (status) => true,
        headers: {
          'Authorization': 'Bearer ${settings.apiKey}',
          if (extraHeaders != null) ...extraHeaders,
        },
      ),
      cancelToken: cancelToken,
    );
    return _normalizeArchiveAtHomeResponse(response);
  }

  String _joinUrl(String base, String path) {
    final normalizedBase =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$normalizedBase$normalizedPath';
  }

  _ArchiveBotResponse _normalizeWrappedResponse(Response response) {
    final data = _coerceResponseData(response.data);
    if (data is Map) {
      return _ArchiveBotResponse(
        code: (data['code'] as num?)?.toInt() ?? response.statusCode ?? 99,
        message: data['msg']?.toString() ??
            data['message']?.toString() ??
            data['error']?.toString() ??
            response.statusMessage ??
            '',
        data: data['data'] is Map
            ? Map<String, dynamic>.from(data['data'] as Map)
            : const <String, dynamic>{},
      );
    }
    return _ArchiveBotResponse(
      code: response.statusCode == 200 ? 0 : response.statusCode ?? 99,
      message: response.statusMessage ?? 'Archive Bot response is not JSON',
      data: const <String, dynamic>{},
    );
  }

  _ArchiveBotResponse _normalizeArchiveAtHomeResponse(Response response) {
    final data = _coerceResponseData(response.data);
    if (data is Map && data['code'] is num) {
      return _normalizeWrappedResponse(response);
    }
    if (response.statusCode != null &&
        response.statusCode! >= 200 &&
        response.statusCode! < 300 &&
        data is Map &&
        data['error'] == null) {
      return _ArchiveBotResponse(
        code: 0,
        message: data['msg']?.toString() ?? data['message']?.toString() ?? 'OK',
        data: Map<String, dynamic>.from(data),
      );
    }
    final message = data is Map
        ? data['error']?.toString() ??
            data['message']?.toString() ??
            data['msg']?.toString()
        : response.statusMessage;
    return _ArchiveBotResponse(
      code: response.statusCode ?? 99,
      message: message == null || message.isEmpty
          ? 'Archive-at-Home request failed'
          : message,
      data: data is Map
          ? Map<String, dynamic>.from(data)
          : const <String, dynamic>{},
    );
  }

  Object? _coerceResponseData(Object? value) {
    if (value is String) {
      try {
        return jsonDecode(value);
      } catch (_) {
        return value;
      }
    }
    return value;
  }
}

class _ArchiveBotResponse {
  const _ArchiveBotResponse({
    required this.code,
    required this.message,
    required this.data,
  });

  final int code;
  final String message;
  final Map<String, dynamic> data;

  bool get isSuccess => code == 0;

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        'data': data,
      };
}
