import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../config/server_config.dart';
import '../core/log.dart';

/// Calls JHenTai public API `GET /api/gallery/fetchImageHash` (same contract as mobile [jh_request.requestGalleryImageHashes]).
class JhPublicClient {
  JhPublicClient(this._config);

  final ServerConfig _config;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 60),
  ));

  /// Returns null on failure, missing secret, or non-success response.
  Future<List<String>?> fetchGalleryImageHashes({required int gid, required String token}) async {
    if (_config.jhApiSecret.isEmpty) {
      return null;
    }
    final base = _config.jhPublicApiBaseUrl;
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    final payload = '${_config.jhAppId}-$ts-$ts';
    final key = utf8.encode(_config.jhApiSecret);
    final sig = base64.encode(Hmac(sha256, key).convert(utf8.encode(payload)).bytes);

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$base/api/gallery/fetchImageHash',
        queryParameters: {'gid': gid, 'token': token},
        options: Options(
          headers: {
            'X-App-Id': _config.jhAppId,
            'X-Timestamp': ts,
            'X-Nonce': ts,
            'X-Signature': sig,
            'Content-Type': 'application/json',
          },
        ),
      );
      final root = response.data;
      if (root == null) return null;
      if (root['code'] != 0) {
        log.warning('JH fetchImageHash error: code=${root['code']} message=${root['message']}');
        return null;
      }
      final data = root['data'];
      if (data is! Map<String, dynamic>) return null;
      final list = data['hashes'];
      if (list is! List) return null;
      return list.map((e) => e.toString()).toList();
    } on DioException catch (e) {
      log.warning('JH fetchImageHash network error: ${e.message}');
      return null;
    } catch (e, s) {
      log.error('JH fetchImageHash failed', e, s);
      return null;
    }
  }
}
