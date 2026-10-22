import 'package:flutter_test/flutter_test.dart';
import 'package:pura_air/services/device_api_client.dart';

void main() {
  test('Device API attaches the current token and preserves method/body',
      () async {
    final client = DeviceApiClient(
      baseUrl: 'https://device-service.example',
      tokenProvider: () async => 'test-token',
      transport: (method, uri, token, body) async {
        expect(method, 'POST');
        expect(uri.path, '/api/devices/PA-TEST/claim');
        expect(token, 'test-token');
        expect(body, {'name': 'Lab'});
        return const DeviceApiResponse(200, '{"role":"owner"}');
      },
    );
    expect(
        (await client.request(
            'POST', '/api/devices/PA-TEST/claim', {'name': 'Lab'}))['role'],
        'owner');
  });
  for (final entry in {
    401: 'invalid_token',
    403: 'owner_required',
    400: 'invalid_name',
    410: 'pairing_code_expired',
    409: 'pairing_code_used',
    429: 'rate_limited',
    503: 'access_sync_pending'
  }.entries) {
    test('API rejection ${entry.key} remains an error with a useful message',
        () async {
      final client = DeviceApiClient(
          baseUrl: 'https://device-service.example',
          tokenProvider: () async => 'test-token',
          transport: (_, __, ___, ____) async =>
              DeviceApiResponse(entry.key, '{"error":"${entry.value}"}'));
      await expectLater(
          client.request('POST', '/api/pairing/redeem'),
          throwsA(isA<DeviceApiException>()
              .having((e) => e.status, 'status', entry.key)
              .having((e) => e.toString().isNotEmpty, 'user message', true)));
    });
  }
  test(
      'missing token, malformed server response and unsafe base URL fail closed',
      () async {
    final missing = DeviceApiClient(
        baseUrl: 'https://device-service.example',
        tokenProvider: () async => null);
    await expectLater(
        missing.request('GET', '/api/devices'),
        throwsA(
            isA<DeviceApiException>().having((e) => e.status, 'status', 401)));
    final malformed = DeviceApiClient(
        baseUrl: 'https://device-service.example',
        tokenProvider: () async => 'test-token',
        transport: (_, __, ___, ____) async =>
            const DeviceApiResponse(500, 'private internal error'));
    await expectLater(
        malformed.request('GET', '/api/devices'),
        throwsA(isA<DeviceApiException>().having(
            (e) => e.toString().contains('private'),
            'no internal error disclosure',
            false)));
    final unsafe = DeviceApiClient(
        baseUrl: 'http://remote.example',
        tokenProvider: () async => 'test-token');
    await expectLater(
        unsafe.request('GET', '/api/devices'),
        throwsA(isA<DeviceApiException>()
            .having((e) => e.code, 'code', 'api_not_configured')));
  });
}
