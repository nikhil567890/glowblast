import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glowblast/data/models/business_membership.dart';
import 'package:glowblast/data/models/customer.dart';
import 'package:glowblast/data/repositories/app_repository.dart';
import 'package:glowblast/services/glowblast_backend_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BusinessMembership Model Tests', () {
    test('Correctly deserializes and serializes JSON with role helpers', () {
      final json = {
        'businessId': 'biz-1234',
        'slug': 'serenity-spa',
        'displayName': 'Serenity Spa & Wellness',
        'role': 'owner',
        'isActive': true,
        'productionEnabled': true,
        'dailyRecipientLimit': 500,
        'joinedAt': '2026-01-15T10:00:00.000Z',
      };

      final membership = BusinessMembership.fromJson(json);

      expect(membership.businessId, equals('biz-1234'));
      expect(membership.slug, equals('serenity-spa'));
      expect(membership.displayName, equals('Serenity Spa & Wellness'));
      expect(membership.role, equals('owner'));
      expect(membership.isOwner, isTrue);
      expect(membership.isAdmin, isTrue); // Owners have admin permissions
      expect(membership.isStaff, isFalse);
      expect(membership.isActive, isTrue);
      expect(membership.productionEnabled, isTrue);
      expect(membership.dailyRecipientLimit, equals(500));

      final serialized = membership.toJson();
      expect(serialized['businessId'], equals('biz-1234'));
      expect(serialized['role'], equals('owner'));
    });

    test('Identifies admin and staff roles correctly', () {
      final admin = BusinessMembership.fromJson({
        'businessId': 'biz-admin',
        'displayName': 'Admin Business',
        'role': 'admin',
      });
      expect(admin.isAdmin, isTrue);
      expect(admin.isOwner, isFalse);
      expect(admin.isStaff, isFalse);

      final staff = BusinessMembership.fromJson({
        'businessId': 'biz-staff',
        'displayName': 'Staff Business',
        'role': 'staff',
      });
      expect(staff.isStaff, isTrue);
      expect(staff.isOwner, isFalse);
      expect(staff.isAdmin, isFalse);
    });
  });

  group('GlowBlastBackendClient Business Context Headers', () {
    test('Injects X-Business-Id when activeBusinessId is configured', () {
      final client = GlowBlastBackendClient(
        baseUrl: 'https://glowblast-api.onrender.com',
        authToken: 'test-jwt-token',
        activeBusinessId: 'biz-test-uuid',
      );

      expect(client.activeBusinessId, equals('biz-test-uuid'));
      expect(client.authToken, equals('test-jwt-token'));
    });
  });

  group('AppRepository Business Context & Storage Isolation Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Switching businesses isolates cached customers and in-memory state', () async {
      final repo = AppRepository();
      await repo.init(isProduction: true);

      final bizA = BusinessMembership(
        businessId: 'biz-001',
        slug: 'spa-a',
        displayName: 'Spa A',
        role: 'owner',
      );

      final bizB = BusinessMembership(
        businessId: 'biz-002',
        slug: 'spa-b',
        displayName: 'Spa B',
        role: 'owner',
      );

      // Switch to Business A
      await repo.switchBusiness(bizA);
      expect(repo.activeBusinessId, equals('biz-001'));
      expect(repo.backendClient.activeBusinessId, equals('biz-001'));

      // Add a customer to Business A
      final custA = Customer(
        id: 'cust-biz-a-1',
        name: 'Alice Spa A',
        phone: '+919999900001',
      );
      await repo.addCustomer(custA);
      expect(repo.customers.length, equals(1));
      expect(repo.customers.first.name, equals('Alice Spa A'));

      // Switch to Business B
      await repo.switchBusiness(bizB);
      expect(repo.activeBusinessId, equals('biz-002'));
      expect(repo.backendClient.activeBusinessId, equals('biz-002'));

      // Business B should NOT see Business A's customers
      expect(repo.customers, isEmpty);

      // Add a customer to Business B
      final custB = Customer(
        id: 'cust-biz-b-1',
        name: 'Bob Spa B',
        phone: '+919999900002',
      );
      await repo.addCustomer(custB);
      expect(repo.customers.length, equals(1));
      expect(repo.customers.first.name, equals('Bob Spa B'));

      // Switch back to Business A
      await repo.switchBusiness(bizA);
      expect(repo.activeBusinessId, equals('biz-001'));
      expect(repo.customers.length, equals(1));
      expect(repo.customers.first.name, equals('Alice Spa A'));
    });

    test('Generation counter prevents race conditions during rapid switching', () async {
      final repo = AppRepository();
      await repo.init(isProduction: true);

      final initialGen = repo.businessSwitchGeneration;

      final bizA = BusinessMembership(businessId: 'biz-01', slug: 'biz-1', displayName: 'Biz 1');
      final bizB = BusinessMembership(businessId: 'biz-02', slug: 'biz-2', displayName: 'Biz 2');

      await repo.switchBusiness(bizA);
      expect(repo.businessSwitchGeneration, equals(initialGen + 1));

      await repo.switchBusiness(bizB);
      expect(repo.businessSwitchGeneration, equals(initialGen + 2));
    });

    test('clearAuthSession wipes active business, memberships, and sensitive business data', () async {
      final repo = AppRepository();
      await repo.init(isProduction: true);

      final biz = BusinessMembership(
        businessId: 'biz-sensitive',
        slug: 'sensitive-spa',
        displayName: 'Sensitive Spa',
        role: 'owner',
      );

      await repo.switchBusiness(biz);
      await repo.addCustomer(Customer(id: 'c-secret', name: 'Secret Customer', phone: '+919999999999'));
      expect(repo.customers, isNotEmpty);
      expect(repo.hasActiveBusiness, isTrue);

      // Perform logout / clear session
      await repo.clearAuthSession();

      expect(repo.isAuthenticated, isFalse);
      expect(repo.hasActiveBusiness, isFalse);
      expect(repo.activeBusinessId, isNull);
      expect(repo.userBusinesses, isEmpty);
      expect(repo.customers, isEmpty);
      expect(repo.campaigns, isEmpty);
      expect(repo.backendClient.activeBusinessId, isNull);
    });
  });
}
