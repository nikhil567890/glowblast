import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glowblast/data/models/auth_user.dart';
import 'package:glowblast/data/repositories/app_repository.dart';
import 'package:glowblast/services/glowblast_backend_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Campaign Dispatch & JWT Auth Tests', () {
    test('1. Login session saved and restores in repository', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = AppRepository();
      await repo.init();

      expect(repo.isAuthenticated, false);
      expect(repo.authToken, null);

      final user = AuthUser(
        id: 'usr_test_123',
        name: 'Test Owner',
        email: 'tester@glowblast.com',
        businessName: 'Glow Spa',
        emailVerified: true,
      );

      await repo.saveAuthSession('jwt_token_sample_abc123', user);

      expect(repo.isAuthenticated, true);
      expect(repo.authToken, 'jwt_token_sample_abc123');
      expect(repo.currentUser?.email, 'tester@glowblast.com');
      expect(repo.backendClient.authToken, 'jwt_token_sample_abc123');

      // Re-initialize repository to verify persistence
      final repo2 = AppRepository();
      await repo2.init();
      expect(repo2.isAuthenticated, true);
      expect(repo2.authToken, 'jwt_token_sample_abc123');
      expect(repo2.backendClient.authToken, 'jwt_token_sample_abc123');
    });

    test('2. JWT attached to protected campaign send requests', () async {
      String? capturedAuthHeader;
      Map<String, dynamic>? capturedBody;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/campaigns/send') {
          capturedAuthHeader = request.headers['Authorization'];
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'success': true,
              'campaignId': capturedBody?['campaignId'],
              'status': 'processing',
              'message': 'Campaign accepted for processing',
            }),
            202,
          );
        }
        return http.Response('{"error": "Not Found"}', 404);
      });

      final client = GlowBlastBackendClient(
        baseUrl: 'https://glowblast-api.onrender.com',
        httpClient: mockClient,
        authToken: 'test_jwt_secure_token',
      );

      final res = await client.sendCampaign(
        campaignId: 'GB-TEST-1',
        campaignName: 'GlowBlast Hello World Test',
        templateName: 'hello_world',
        templateLanguage: 'en_US',
        recipients: [
          {'localCustomerId': 'c1', 'name': 'Authorized Tester', 'phone': '919182769155'},
        ],
      );

      expect(res['success'], true);
      expect(capturedAuthHeader, 'Bearer test_jwt_secure_token');
      expect(capturedBody?['campaignName'], 'GlowBlast Hello World Test');
      expect(capturedBody?['templateName'], 'hello_world');
      expect(capturedBody?['templateLanguage'], 'en_US');
      expect(capturedBody?['recipients'].length, 1);
    });

    test('3. Explicit token parameter overrides default client authToken', () async {
      String? capturedAuthHeader;

      final mockClient = MockClient((request) async {
        capturedAuthHeader = request.headers['Authorization'];
        return http.Response(jsonEncode({'success': true}), 202);
      });

      final client = GlowBlastBackendClient(
        baseUrl: 'https://glowblast-api.onrender.com',
        httpClient: mockClient,
        authToken: 'default_token',
      );

      await client.sendCampaign(
        campaignId: 'GB-TEST-2',
        campaignName: 'Custom Token Test',
        templateName: 'hello_world',
        recipients: [{'localCustomerId': 'c1', 'name': 'Tester', 'phone': '919182769155'}],
        token: 'overridden_jwt_token',
      );

      expect(capturedAuthHeader, 'Bearer overridden_jwt_token');
    });

    test('4. Correct campaign JSON generated without null properties', () async {
      Map<String, dynamic>? capturedBody;

      final mockClient = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'success': true}), 202);
      });

      final client = GlowBlastBackendClient(
        baseUrl: 'https://glowblast-api.onrender.com',
        httpClient: mockClient,
      );

      await client.sendCampaign(
        campaignId: 'GB-TEST-3',
        campaignName: 'Null Check Test',
        templateName: 'hello_world',
        businessName: null,
        templateId: null,
        templateVariables: null,
        metadata: null,
        recipients: [{'localCustomerId': 'c1', 'name': 'Tester', 'phone': '919182769155'}],
      );

      expect(capturedBody?.containsKey('businessName'), false);
      expect(capturedBody?.containsKey('templateId'), false);
      expect(capturedBody?.containsKey('templateVariables'), false);
      expect(capturedBody?.containsKey('metadata'), false);
      expect(capturedBody?['campaignId'], 'GB-TEST-3');
      expect(capturedBody?['campaignName'], 'Null Check Test');
    });

    test('5. Backend 401 UNAUTHORIZED handled and parsed cleanly', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'UNAUTHORIZED',
              'message': 'Authentication required',
            },
          }),
          401,
        );
      });

      final client = GlowBlastBackendClient(
        baseUrl: 'https://glowblast-api.onrender.com',
        httpClient: mockClient,
      );

      final res = await client.sendCampaign(
        campaignId: 'GB-TEST-4',
        campaignName: 'Unauthorized Test',
        templateName: 'hello_world',
        recipients: [{'phone': '919182769155'}],
      );

      expect(res['success'], false);
      expect(res['statusCode'], 401);
      expect(res['error']['code'], 'UNAUTHORIZED');
      expect(res['error']['message'], 'Authentication required');
    });

    test('6. Backend 400 VALIDATION_ERROR with fields parsed cleanly', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'VALIDATION_ERROR',
              'message': 'Invalid campaign data: recipients',
              'fields': ['recipients'],
            },
          }),
          400,
        );
      });

      final client = GlowBlastBackendClient(
        baseUrl: 'https://glowblast-api.onrender.com',
        httpClient: mockClient,
      );

      final res = await client.sendCampaign(
        campaignId: 'GB-TEST-5',
        campaignName: 'Bad Payload Test',
        templateName: 'hello_world',
        recipients: [],
      );

      expect(res['success'], false);
      expect(res['statusCode'], 400);
      expect(res['error']['code'], 'VALIDATION_ERROR');
      expect(res['error']['fields'], ['recipients']);
    });

    test('7. Meta API error handling', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 131031,
              'message': 'WhatsApp Business Account is restricted.',
            },
          }),
          400,
        );
      });

      final client = GlowBlastBackendClient(
        baseUrl: 'https://glowblast-api.onrender.com',
        httpClient: mockClient,
      );

      final res = await client.sendCampaign(
        campaignId: 'GB-TEST-6',
        campaignName: 'Meta Restriction Test',
        templateName: 'hello_world',
        recipients: [{'phone': '919182769155'}],
      );

      expect(res['success'], false);
      expect(res['error']['code'], 131031);
    });

    test('8. Authorized Meta Tester customer exists in repository', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = AppRepository();
      await repo.init();

      final tester = repo.customers.where((c) =>
        c.phone.replaceAll(RegExp(r'\D'), '').endsWith('9182769155')
      ).firstOrNull;

      expect(tester, isNotNull);
      expect(tester!.isOptedOut, false);
      expect(tester.name, 'Authorized Meta Tester');
    });
  });
}
