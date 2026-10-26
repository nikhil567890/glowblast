import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glowblast/data/models/business_member.dart';
import 'package:glowblast/data/models/business_invitation.dart';
import 'package:glowblast/data/models/business_membership.dart';
import 'package:glowblast/data/repositories/app_repository.dart';
import 'package:glowblast/services/glowblast_backend_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 4: Flutter Team Management & Role Models', () {
    test('1. BusinessMember model correctly parses JSON and identifies roles', () {
      final json = {
        'businessId': 'biz-123',
        'userId': 'usr-456',
        'role': 'owner',
        'joinedAt': '2026-10-26T12:00:00Z',
        'name': 'Priya Sharma',
        'email': 'priya@lotus.com',
      };

      final member = BusinessMember.fromJson(json);
      expect(member.businessId, equals('biz-123'));
      expect(member.userId, equals('usr-456'));
      expect(member.role, equals('owner'));
      expect(member.isOwner, isTrue);
      expect(member.isAdmin, isTrue);
      expect(member.isStaff, isFalse);
      expect(member.displayName, equals('Priya Sharma'));

      final staffMember = BusinessMember(
        businessId: 'biz-123',
        userId: 'usr-789',
        role: 'staff',
        email: 'staff@lotus.com',
      );
      expect(staffMember.isOwner, isFalse);
      expect(staffMember.isAdmin, isFalse);
      expect(staffMember.isStaff, isTrue);
      expect(staffMember.displayName, equals('staff'));
    });

    test('2. BusinessInvitation model detects expired vs pending status', () {
      final activeInv = BusinessInvitation(
        id: 'inv-1',
        businessId: 'biz-123',
        email: 'newuser@lotus.com',
        role: 'staff',
        expiresAt: DateTime.now().add(const Duration(days: 7)),
        status: 'pending',
      );
      expect(activeInv.isExpired, isFalse);
      expect(activeInv.isPending, isTrue);

      final expiredInv = BusinessInvitation(
        id: 'inv-2',
        businessId: 'biz-123',
        email: 'olduser@lotus.com',
        role: 'admin',
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
        status: 'pending',
      );
      expect(expiredInv.isExpired, isTrue);
      expect(expiredInv.isPending, isFalse);
    });

    test('3. GlowBlastBackendClient sends team management requests with tenant isolation headers', () async {
      String? capturedPath;
      String? capturedMethod;
      String? capturedBusinessHeader;
      String? capturedBody;

      final mockClient = MockClient((request) async {
        capturedPath = request.url.path;
        capturedMethod = request.method;
        capturedBusinessHeader = request.headers['X-Business-Id'];
        capturedBody = request.body;

        if (request.url.path.endsWith('/members') && request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'success': true,
              'members': [
                {
                  'businessId': 'biz-mock-1',
                  'userId': 'usr-1',
                  'role': 'owner',
                  'name': 'Owner User',
                  'email': 'owner@biz.com',
                },
                {
                  'businessId': 'biz-mock-1',
                  'userId': 'usr-2',
                  'role': 'staff',
                  'name': 'Staff User',
                  'email': 'staff@biz.com',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.url.path.endsWith('/invitations') && request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'success': true,
              'invitation': {
                'id': 'inv-mock-99',
                'businessId': 'biz-mock-1',
                'email': 'invitee@biz.com',
                'role': 'staff',
              },
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response(jsonEncode({'success': true}), 200);
      });

      final client = GlowBlastBackendClient(
        baseUrl: 'https://test-api.glowblast.com',
        activeBusinessId: 'biz-mock-1',
        authToken: 'jwt-token-123',
        httpClient: mockClient,
      );

      // Test getBusinessMembers
      final members = await client.getBusinessMembers();
      expect(capturedPath, equals('/api/businesses/biz-mock-1/members'));
      expect(capturedMethod, equals('GET'));
      expect(capturedBusinessHeader, equals('biz-mock-1'));
      expect(members.length, equals(2));
      expect(members[0].isOwner, isTrue);
      expect(members[1].isStaff, isTrue);

      // Test inviteBusinessMember
      final inviteResult = await client.inviteBusinessMember(
        email: 'invitee@biz.com',
        role: 'staff',
      );
      expect(capturedPath, equals('/api/businesses/biz-mock-1/invitations'));
      expect(capturedMethod, equals('POST'));
      expect(capturedBusinessHeader, equals('biz-mock-1'));
      expect(inviteResult['success'], isTrue);
      final body = jsonDecode(capturedBody!);
      expect(body['email'], equals('invitee@biz.com'));
      expect(body['role'], equals('staff'));
    });

    test('4. AppRepository exposes role getters and syncs business profile update', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = AppRepository();
      await repo.init();

      // Initial mock business setup
      final ownerBiz = BusinessMembership(
        businessId: 'biz-owner-99',
        slug: 'lotus-spa',
        displayName: 'Lotus Spa',
        role: 'owner',
      );

      await repo.switchBusiness(ownerBiz);
      expect(repo.isBusinessOwner, isTrue);
      expect(repo.isBusinessAdmin, isTrue);
      expect(repo.isBusinessStaff, isFalse);
      expect(repo.activeBusiness?.displayName, equals('Lotus Spa'));

      // Switch to staff business
      final staffBiz = BusinessMembership(
        businessId: 'biz-staff-88',
        slug: 'branch-spa',
        displayName: 'Branch Spa',
        role: 'staff',
      );

      await repo.switchBusiness(staffBiz);
      expect(repo.isBusinessOwner, isFalse);
      expect(repo.isBusinessAdmin, isFalse);
      expect(repo.isBusinessStaff, isTrue);
    });
  });
}
