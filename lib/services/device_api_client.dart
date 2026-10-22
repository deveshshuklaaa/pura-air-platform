import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class DeviceApiException implements Exception {
  final String code;
  final int status;
  const DeviceApiException(this.code, [this.status = 0]);

  @override
  String toString() => switch (code) {
        'authentication_required' || 'invalid_token' => 'Please sign in again.',
        'registered_account_required' =>
          'Sign in with a registered account to manage devices.',
        'owner_required' => 'Only the device owner can do this.',
        'device_unavailable' => 'Device is unavailable or already owned.',
        'invalid_pairing_code' => 'Pairing code is invalid.',
        'pairing_code_expired' =>
          'Pairing code has expired. Ask the owner for a new code.',
        'pairing_code_used' => 'This pairing code has already been used.',
        'rate_limited' => 'Too many attempts. Please try again later.',
        'invalid_name' => 'Enter a name of 1–100 characters.',
        'access_sync_pending' =>
          'The change was saved, but device access is still syncing. Refresh your devices before retrying.',
        'api_not_configured' => 'Device service is not configured.',
        _ => 'Device request failed. Please try again.',
      };
}

class DeviceApiResponse {
  final int status;
  final String body;
  const DeviceApiResponse(this.status, this.body);
}

typedef DeviceApiTransport = Future<DeviceApiResponse> Function(
    String method, Uri uri, String token, Map<String, dynamic> body);

class DeviceApiClient {
  final String baseUrl;
  final Future<String?> Function() _token;
  final DeviceApiTransport _transport;

  DeviceApiClient({
    this.baseUrl = const String.fromEnvironment('PURA_API_BASE_URL'),
    Future<String?> Function()? tokenProvider,
    DeviceApiTransport? transport,
  })  : _token = tokenProvider ??
            (() async => FirebaseAuth.instance.currentUser?.getIdToken()),
        _transport = transport ?? _send;

  static Future<DeviceApiResponse> _send(
      String method, Uri uri, String token, Map<String, dynamic> body) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.openUrl(method, uri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.contentType = ContentType.json;
      if (method != 'GET') request.write(jsonEncode(body));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return DeviceApiResponse(response.statusCode, text);
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> request(String method, String path,
      [Map<String, dynamic> body = const {}]) async {
    final base = Uri.tryParse(baseUrl);
    final local = kDebugMode &&
        base != null &&
        ['localhost', '127.0.0.1', '10.0.2.2'].contains(base.host);
    if (base == null ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        (base.scheme != 'https' && !(local && base.scheme == 'http'))) {
      throw const DeviceApiException('api_not_configured');
    }
    try {
      final token = await _token();
      if (token == null) {
        throw const DeviceApiException('authentication_required', 401);
      }
      final response = await _transport(method, base.resolve(path), token, body)
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.status < 200 || response.status >= 300) {
        throw DeviceApiException(
            data['error'] as String? ?? 'service_unavailable', response.status);
      }
      return data;
    } on DeviceApiException {
      rethrow;
    } catch (_) {
      throw const DeviceApiException('service_unavailable');
    }
  }
}
