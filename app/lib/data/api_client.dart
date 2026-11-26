import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// The backend wraps reads as {"data": ..., "updated_at": ISO, "stale": bool}.
class Envelope {
  const Envelope({required this.data, required this.updatedAt, this.stale = false});

  final Object? data;
  final DateTime updatedAt;
  final bool stale;

  factory Envelope.fromJson(Map<String, dynamic> j) => Envelope(
        data: j['data'],
        updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '')?.toUtc() ?? DateTime.now().toUtc(),
        stale: j['stale'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {'data': data, 'updated_at': updatedAt.toIso8601String(), 'stale': stale};
}

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// No connection / timeout, as opposed to the server answering with an error.
  bool get isNetwork => statusCode == null;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client}) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  static const _timeout = Duration(seconds: 10);

  Uri uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> getJson(String path, [Map<String, String>? query]) =>
      _send(() => _client.get(uri(path, query), headers: {'Accept': 'application/json'}));

  /// POST/PUT a JSON body. [headers] is for auth (`Authorization: Bearer ...`).
  Future<Map<String, dynamic>> sendJson(
    String method,
    String path,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) {
    final allHeaders = {'Accept': 'application/json', 'Content-Type': 'application/json', ...headers};
    final encoded = jsonEncode(body);
    return _send(() => switch (method) {
          'POST' => _client.post(uri(path), headers: allHeaders, body: encoded),
          'PUT' => _client.put(uri(path), headers: allHeaders, body: encoded),
          _ => throw ArgumentError.value(method, 'method'),
        });
  }

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() request) async {
    final http.Response res;
    try {
      res = await request().timeout(_timeout);
    } on SocketException catch (e) {
      throw ApiException('offline: ${e.message}');
    } on TimeoutException {
      throw ApiException('timeout');
    } on http.ClientException catch (e) {
      throw ApiException('offline: ${e.message}');
    }
    if (res.statusCode >= 400) {
      throw ApiException('HTTP ${res.statusCode}: ${res.body}', statusCode: res.statusCode);
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Envelope> getEnvelope(String path, [Map<String, String>? query]) async =>
      Envelope.fromJson(await getJson(path, query));
}
