import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:glowblast/services/excel_service.dart';
import 'package:glowblast/data/models/settings_model.dart';
import 'package:glowblast/data/models/customer.dart';
import 'package:glowblast/data/models/campaign.dart';
import 'package:glowblast/data/models/whatsapp_template.dart';
import 'package:glowblast/data/repositories/app_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Phone Number Validation Tests', () {
    test('extractClean10Digits handles standard, prefix, and spaced phone numbers', () {
      expect(ExcelService.extractClean10Digits('9876543210'), '9876543210');
      expect(ExcelService.extractClean10Digits('+91 98765 43210'), '9876543210');
      expect(ExcelService.extractClean10Digits('+91-98765-43210'), '9876543210');
      expect(ExcelService.extractClean10Digits('09876543210'), '9876543210');
      expect(ExcelService.extractClean10Digits('919876543210'), '9876543210');
    });

    test('isValidIndianPhone accurately validates Indian mobile numbers', () {
      expect(ExcelService.isValidIndianPhone('9876543210'), isTrue);
      expect(ExcelService.isValidIndianPhone('+91 87654 32109'), isTrue);
      expect(ExcelService.isValidIndianPhone('7654321098'), isTrue);
      expect(ExcelService.isValidIndianPhone('6543210987'), isTrue);

      // Invalid cases
      expect(ExcelService.isValidIndianPhone('5432109876'), isFalse); // Starts with 5
      expect(ExcelService.isValidIndianPhone('2234567890'), isFalse); // Starts with 2
      expect(ExcelService.isValidIndianPhone('98765'), isFalse); // Too short
      expect(ExcelService.isValidIndianPhone('NOT_A_PHONE'), isFalse); // Letters
      expect(ExcelService.isValidIndianPhone(''), isFalse); // Empty
    });

    test('formatIndianPhone formats into clean text with +91 prefix', () {
      expect(ExcelService.formatIndianPhone('9876543210'), '+91 98765 43210');
      expect(ExcelService.formatIndianPhone('+91 98765-43210'), '+91 98765 43210');
    });
  });

  group('Message Personalization Tests', () {
    test('resolves {name}, {customer_name}, {spa_name}, and {business_name}', () {
      const template = '🌸 Hi {name}! Welcome to {business_name}. Book your session at {spa_name} with code GLOW.';
      final resolved = template
          .replaceAll('{name}', 'Aarav')
          .replaceAll('{customer_name}', 'Aarav')
          .replaceAll('{spa_name}', 'Lotus Wellness')
          .replaceAll('{business_name}', 'Lotus Wellness');

      expect(resolved, '🌸 Hi Aarav! Welcome to Lotus Wellness. Book your session at Lotus Wellness with code GLOW.');
      expect(resolved.contains('{name}'), isFalse);
      expect(resolved.contains('{spa_name}'), isFalse);
      expect(resolved.contains('{business_name}'), isFalse);
    });
  });

  group('Excel Parser & 200-Row Sample Dataset Tests', () {
    test('generate200RowTestSampleBytes creates 200 rows with 190 valid, 7 duplicates, 3 invalid phones', () {
      final bytes = ExcelService.generate200RowTestSampleBytes();
      expect(bytes.isNotEmpty, isTrue);

      final result = ExcelService.parseAndValidate(Uint8List.fromList(bytes));

      expect(result.totalRows, 200);
      expect(result.validCount, 190);
      expect(result.duplicateCount, 7);
      expect(result.invalidPhoneCount, 3);
      expect(result.otherErrorCount, 0);

      // Verify customer format
      final first = result.validCustomers.first;
      expect(first.name.isNotEmpty, isTrue);
      expect(first.phone.startsWith('+91 '), isTrue);
      expect(ExcelService.isValidIndianPhone(first.phone), isTrue);
    });

    test('generateSampleTemplateBytes generates template headers', () {
      final bytes = ExcelService.generateSampleTemplateBytes();
      expect(bytes.isNotEmpty, isTrue);

      final result = ExcelService.parseAndValidate(Uint8List.fromList(bytes));
      expect(result.validCount, 4);
    });
  });

  group('AppSettings & Profile Tests', () {
    test('hasProfile returns false when empty and true when filled', () {
      final emptySettings = AppSettings();
      expect(emptySettings.hasProfile, isFalse);

      final filled = emptySettings.copyWith(
        fullName: 'Pooja Sharma',
        businessName: 'Aura Spa',
        phone: '+91 98765 43210',
      );
      expect(filled.hasProfile, isTrue);
      expect(filled.spaName, 'Aura Spa');
    });

    test('legacy demo profiles (Priya / Serenity Spa) are migrated to empty profile', () {
      final legacyJson = {
        'userName': 'Priya',
        'spaName': 'Serenity Spa & Wellness',
        'userPhone': '+91 98765 00000',
        'themeMode': 'light',
      };
      final migrated = AppSettings.fromJson(legacyJson);
      expect(migrated.hasProfile, isFalse);
      expect(migrated.fullName, '');
      expect(migrated.businessName, '');
    });

    test('backendUrl defaults to https://glowblast-api.onrender.com', () {
      final settings = AppSettings();
      expect(settings.backendUrl, 'https://glowblast-api.onrender.com');
    });

    test('stale 10.0.2.2, localhost, and LAN development URLs are migrated to cloud backend', () {
      final stale10Json = {'backendUrl': 'http://10.0.2.2:3000'};
      expect(AppSettings.fromJson(stale10Json).backendUrl, 'https://glowblast-api.onrender.com');

      final staleLocalhostJson = {'backendUrl': 'http://localhost:3000'};
      expect(AppSettings.fromJson(staleLocalhostJson).backendUrl, 'https://glowblast-api.onrender.com');

      final staleLanJson = {'backendUrl': 'http://192.168.1.50:3000'};
      expect(AppSettings.fromJson(staleLanJson).backendUrl, 'https://glowblast-api.onrender.com');

      final emptyJson = {'backendUrl': ''};
      expect(AppSettings.fromJson(emptyJson).backendUrl, 'https://glowblast-api.onrender.com');
    });

    test('valid custom production HTTPS URL is preserved', () {
      final customJson = {'backendUrl': 'https://api.custom-glowblast.com'};
      expect(AppSettings.fromJson(customJson).backendUrl, 'https://api.custom-glowblast.com');
    });
  });

  group('AppRepository V3 KPIs & Operations Tests', () {
    test('Initializes with 200 customers, 12 opted-out, correct computed KPIs', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = AppRepository();
      await repository.init();

      expect(repository.totalCustomersCount, 200);
      expect(repository.optedOutCustomersCount, 12);
      expect(repository.eligibleCustomersCount, 188);

      // Total messages sent is computed from sent campaigns
      final expectedSent = repository.sentCampaigns.fold(0, (sum, c) => sum + c.messagesSent);
      expect(repository.totalMessagesSent, expectedSent);
      expect(repository.totalMessagesSent > 0, isTrue);

      // Delivery rate computed
      expect(repository.overallDeliveryRate > 0, isTrue);

      // Best campaign is based on highest read count
      expect(repository.bestPerformingCampaign, isNotNull);
    });

    test('resetDemoData with clearProfile resets profile', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = AppRepository();
      await repository.init();

      await repository.updateSettings(
        repository.settings.copyWith(
          fullName: 'Test Owner',
          businessName: 'Test Spa',
          phone: '+91 98765 43210',
        ),
      );
      expect(repository.settings.hasProfile, isTrue);

      // Reset keeping profile
      await repository.resetDemoData(clearProfile: false);
      expect(repository.settings.hasProfile, isTrue);
      expect(repository.settings.fullName, 'Test Owner');

      // Reset clearing profile
      await repository.resetDemoData(clearProfile: true);
      expect(repository.settings.hasProfile, isFalse);
      expect(repository.settings.fullName, '');
    });

    test('AppRepository migrates stale 10.0.2.2 in SharedPreferences to cloud backend', () async {
      SharedPreferences.setMockInitialValues({
        'glowblast_is_initialized_v3': true,
        'glowblast_settings_v3': '{"fullName":"Dr. Pooja","businessName":"Aura Spa","phone":"+91 98765 43210","backendUrl":"http://10.0.2.2:3000"}',
      });

      final repository = AppRepository();
      await repository.init();

      expect(repository.settings.backendUrl, 'https://glowblast-api.onrender.com');
      expect(repository.backendClient.baseUrl, 'https://glowblast-api.onrender.com');

      final prefs = await SharedPreferences.getInstance();
      final persisted = prefs.getString('glowblast_settings_v3');
      expect(persisted?.contains('https://glowblast-api.onrender.com'), isTrue);
      expect(persisted?.contains('10.0.2.2'), isFalse);
    });
  });

  group('Campaign Model & State Semantics Tests', () {
    test('Campaign model does not fake messagesSent from recipients count', () {
      final json = {
        'id': 'camp_123',
        'name': 'Monsoon Glow',
        'month': 'Oct',
        'date': '2026-10-04T12:00:00.000Z',
        'channel': 'WhatsApp',
        'targetAudience': 'All',
        'messageContent': 'Hello!',
        'recipients': 5,
        // messagesSent omitted or 0
        'delivered': 0,
        'read': 0,
        'failed': 5,
        'replied': 0,
        'status': 'Failed',
      };

      final campaign = Campaign.fromJson(json);
      expect(campaign.recipients, 5);
      expect(campaign.messagesSent, 0); // Must be 0, NOT 5
      expect(campaign.failed, 5);
      expect(campaign.status, 'Failed');
    });

    test('deliveryRate calculates based on actual messagesSent', () {
      final campaign = Campaign(
        id: 'camp_rate',
        name: 'Rate Test',
        month: 'Oct',
        date: DateTime.now(),
        channel: 'WhatsApp',
        targetAudience: 'All',
        messageContent: 'Test',
        recipients: 10,
        accepted: 8,
        messagesSent: 8,
        delivered: 4,
        read: 2,
        failed: 2,
        replied: 0,
        status: 'Completed with Errors',
      );

      // 4 delivered out of 8 sent = 50.0%
      expect(campaign.deliveryRate, 50.0);
      expect(campaign.readRate, 50.0); // 2 read out of 4 delivered = 50%
      expect(campaign.accepted, 8);
    });

    test('Campaign copyWith correctly preserves accepted and template fields', () {
      final campaign = Campaign(
        id: 'c1',
        name: 'Test',
        month: 'Oct',
        date: DateTime.now(),
        channel: 'WhatsApp',
        targetAudience: 'All',
        messageContent: 'Test',
        recipients: 2,
        accepted: 2,
        messagesSent: 2,
        delivered: 2,
        read: 1,
        failed: 0,
        replied: 0,
        status: 'Completed',
        templateName: 'hello_world',
      );

      final updated = campaign.copyWith(status: 'Completed', delivered: 2);
      expect(updated.accepted, 2);
      expect(updated.templateName, 'hello_world');
      expect(updated.status, 'Completed');
    });
  });

  group('WhatsAppTemplate Model & Management Tests', () {
    test('WhatsAppTemplate approval state gates enforce send eligibility', () {
      final approved = WhatsAppTemplate(
        id: 'tpl_1',
        name: 'birthday_offer',
        displayName: 'Birthday Special',
        status: 'approved',
        metaStatus: 'APPROVED',
        body: 'Happy birthday {name} from {business_name}!',
        variables: ['name', 'business_name'],
      );

      final draft = WhatsAppTemplate(
        id: 'tpl_2',
        name: 'vip_invitation',
        displayName: 'VIP Only',
        status: 'draft',
        metaStatus: 'NOT_SUBMITTED',
        body: 'VIP only: {name}',
        variables: ['name'],
      );

      final pending = WhatsAppTemplate(
        id: 'tpl_3',
        name: 'summer_sale',
        displayName: 'Summer Sale',
        status: 'pending_approval',
        metaStatus: 'PENDING',
        body: 'Summer sale at {business_name}',
        variables: ['business_name'],
      );

      expect(approved.isApproved, isTrue);
      expect(approved.canSend, isTrue);

      expect(draft.isApproved, isFalse);
      expect(draft.canSend, isFalse);
      expect(draft.isDraft, isTrue);

      expect(pending.isApproved, isFalse);
      expect(pending.canSend, isFalse);
      expect(pending.isPending, isTrue);
    });

    test('resolvePreview correctly replaces placeholders with provided customer and spa name', () {
      final tpl = WhatsAppTemplate(
        id: 'tpl_bday',
        name: 'birthday_offer',
        displayName: 'Birthday Offer',
        status: 'approved',
        body: 'Hi {name}, enjoy 30% OFF at {business_name}!',
        variables: ['name', 'business_name'],
      );

      final preview = tpl.resolvePreview(
        customerName: 'Nikhil',
        businessName: 'Luxspa',
      );

      expect(preview, 'Hi Nikhil, enjoy 30% OFF at Luxspa!');
      expect(preview.contains('{name}'), isFalse);
      expect(preview.contains('{business_name}'), isFalse);
    });

    test('getMetaNumberedBody correctly formats Meta numbered placeholders', () {
      final tpl = WhatsAppTemplate(
        id: 'tpl_bday',
        name: 'birthday_offer',
        displayName: 'Birthday Offer',
        status: 'approved',
        body: 'Hi {name}, enjoy 30% OFF at {business_name}!',
        variables: ['name', 'business_name'],
      );

      final metaBody = tpl.getMetaNumberedBody();
      expect(metaBody, 'Hi {{1}}, enjoy 30% OFF at {{2}}!');

      final mapping = tpl.getMetaParameterMapping();
      expect(mapping['name'], '{{1}}');
      expect(mapping['business_name'], '{{2}}');
    });

    test('WhatsAppTemplate serialization and deserialization preserves all fields', () {
      final tpl = WhatsAppTemplate(
        id: 'tpl_test',
        name: 'promo_blast',
        displayName: 'Promo Blast',
        description: 'Test description',
        category: 'MARKETING',
        language: 'en_US',
        status: 'approved',
        metaStatus: 'APPROVED',
        body: 'Hello {name}!',
        variables: ['name'],
        metaTemplateId: 'meta_123',
      );

      final json = tpl.toJson();
      final revived = WhatsAppTemplate.fromJson(json);

      expect(revived.id, 'tpl_test');
      expect(revived.name, 'promo_blast');
      expect(revived.displayName, 'Promo Blast');
      expect(revived.description, 'Test description');
      expect(revived.category, 'MARKETING');
      expect(revived.language, 'en_US');
      expect(revived.status, 'approved');
      expect(revived.isApproved, isTrue);
      expect(revived.canSend, isTrue);
      expect(revived.metaTemplateId, 'meta_123');
      expect(revived.variables, ['name']);
    });
  });

  group('Three-Mode Messaging & Opt-In Consent Tests', () {
    test('Customer model defaults to hasWhatsAppConsent = false', () {
      final customer = Customer(
        id: 'cust_sample_1',
        name: 'Demo Client',
        phone: '+91 98765 43210',
      );

      expect(customer.hasWhatsAppConsent, isFalse);
      expect(customer.consentRecordedAt, isNull);
    });

    test('Customer model serializes and deserializes consent metadata correctly', () {
      final consentedDate = DateTime.parse('2026-10-12T14:30:00.000Z');
      final customer = Customer(
        id: 'cust_consented_1',
        name: 'Pooja',
        phone: '+91 95022 59203',
        hasWhatsAppConsent: true,
        consentRecordedAt: consentedDate,
      );

      final json = customer.toJson();
      final restored = Customer.fromJson(json);

      expect(restored.hasWhatsAppConsent, isTrue);
      expect(restored.consentRecordedAt, consentedDate);
    });

    test('AppSettings handles Demo, Developer Test, and Live Production modes', () {
      final demoSettings = AppSettings(messagingMode: 'demo');
      expect(demoSettings.isDemoMode, isTrue);
      expect(demoSettings.isWhatsAppTestMode, isFalse);
      expect(demoSettings.isWhatsAppProductionMode, isFalse);
      expect(demoSettings.isRealWhatsAppMode, isFalse);

      final testSettings = AppSettings(messagingMode: 'testMode');
      expect(testSettings.isDemoMode, isFalse);
      expect(testSettings.isWhatsAppTestMode, isTrue);
      expect(testSettings.isWhatsAppProductionMode, isFalse);
      expect(testSettings.isRealWhatsAppMode, isTrue);

      final prodSettings = AppSettings(messagingMode: 'production');
      expect(prodSettings.isDemoMode, isFalse);
      expect(prodSettings.isWhatsAppTestMode, isFalse);
      expect(prodSettings.isWhatsAppProductionMode, isTrue);
      expect(prodSettings.isRealWhatsAppMode, isTrue);
    });

    test('WhatsAppTemplate separates test and production mode templates', () {
      final testTemplate = WhatsAppTemplate(
        id: 'tpl_hello',
        name: 'hello_world',
        displayName: 'Hello World Fixture',
        status: 'approved',
        body: 'Hello World',
        mode: 'test',
      );

      final prodTemplate = WhatsAppTemplate(
        id: 'tpl_prod_1',
        name: 'monsoon_glow_offer',
        displayName: 'Monsoon Glow Offer',
        status: 'approved',
        body: 'Hi {name}, enjoy our monsoon glow offer!',
        mode: 'production',
        wabaId: '3226959717495309',
      );

      expect(testTemplate.isTest, isTrue);
      expect(testTemplate.isProduction, isFalse);

      expect(prodTemplate.isProduction, isTrue);
      expect(prodTemplate.wabaId, '3226959717495309');
    });

    test('Campaign model retains explicit mode attribute', () {
      final campaign = Campaign(
        id: 'camp_live_1',
        name: 'Live Diwali Broadcast',
        month: 'Oct',
        date: DateTime.now(),
        channel: 'WhatsApp',
        targetAudience: 'Consented VIPs',
        messageContent: 'Happy Diwali!',
        recipients: 10,
        messagesSent: 10,
        delivered: 9,
        read: 7,
        failed: 1,
        replied: 2,
        mode: 'production',
      );

      expect(campaign.mode, 'production');
      expect(campaign.isProduction, isTrue);

      final json = campaign.toJson();
      final restored = Campaign.fromJson(json);
      expect(restored.mode, 'production');
      expect(restored.isProduction, isTrue);
    });

    test('Production mode with zero templates returns empty activeTemplates without falling back to test templates', () async {
      SharedPreferences.setMockInitialValues({
        'glowblast_is_initialized_v3': true,
        'glowblast_settings_v3': '{"fullName":"Nikhil","businessName":"Spa","phone":"+91 95022 59203","messagingMode":"production"}',
        // Templates list containing only test templates
        'glowblast_templates_v3': '[{"id":"tpl_hello","name":"hello_world","displayName":"Hello World","status":"approved","body":"Hello","mode":"test","language":"en_US"},{"id":"tpl_diwali","name":"diwali_offer","displayName":"Diwali Offer","status":"draft","body":"Offer","mode":"test","language":"en_US"}]',
      });

      final repository = AppRepository();
      await repository.init();

      expect(repository.settings.isWhatsAppProductionMode, isTrue);
      // activeTemplates MUST be completely empty when no production templates exist
      expect(repository.activeTemplates, isEmpty);
      expect(repository.activeApprovedTemplates, isEmpty);

      // getTemplateByName MUST return null for test templates when in production mode
      expect(repository.getTemplateByName('hello_world'), isNull);
      expect(repository.getTemplateByName('diwali_offer'), isNull);
    });

    test('Production mode retrieves approved diwali_spa_offer with language en and WABA 3226959717495309 while isolating test templates', () async {
      SharedPreferences.setMockInitialValues({
        'glowblast_is_initialized_v3': true,
        'glowblast_settings_v3': '{"fullName":"Nikhil","businessName":"Spa","phone":"+91 95022 59203","messagingMode":"production"}',
        'glowblast_templates_v3': '[{"id":"tpl_diwali","name":"diwali_offer","displayName":"Diwali Offer","status":"draft","body":"Offer","mode":"test","wabaId":"1633948435034571","language":"en_US"},{"id":"tpl_prod_diwali_spa_offer_en","name":"diwali_spa_offer","displayName":"Diwali Spa Offer","status":"approved","metaStatus":"APPROVED","metaTemplateId":"1851386776000198","body":"Celebrate Diwali with 40% off","mode":"production","wabaId":"3226959717495309","language":"en"}]',
      });

      final repository = AppRepository();
      await repository.init();

      expect(repository.settings.isWhatsAppProductionMode, isTrue);

      // Verify activeTemplates returns ONLY the production template
      expect(repository.activeTemplates.length, 1);
      final prodTpl = repository.activeTemplates.first;
      expect(prodTpl.name, 'diwali_spa_offer');
      expect(prodTpl.language, 'en'); // Exact language 'en'
      expect(prodTpl.status, 'approved');
      expect(prodTpl.metaStatus, 'APPROVED');
      expect(prodTpl.metaTemplateId, '1851386776000198');
      expect(prodTpl.wabaId, '3226959717495309');
      expect(prodTpl.isProduction, isTrue);

      // activeApprovedTemplates must contain it
      expect(repository.activeApprovedTemplates.length, 1);
      expect(repository.activeApprovedTemplates.first.name, 'diwali_spa_offer');

      // getTemplateByName resolves diwali_spa_offer
      final fetched = repository.getTemplateByName('diwali_spa_offer');
      expect(fetched, isNotNull);
      expect(fetched!.name, 'diwali_spa_offer');
      expect(fetched.isProduction, isTrue);

      // Old test template diwali_offer is NOT accessible in production mode
      expect(repository.getTemplateByName('diwali_offer'), isNull);
    });
  });

  group('Customer WhatsApp Consent Management Tests', () {
    test('Customer model defaults to false for marketing and utility consent (no auto-consent)', () {
      final customer = Customer(
        id: 'cust_new_1',
        name: 'Aarav Patel',
        phone: '+91 98765 43210',
      );

      expect(customer.hasMarketingConsent, isFalse);
      expect(customer.hasUtilityConsent, isFalse);
      expect(customer.hasWhatsAppConsent, isFalse);
      expect(customer.marketingConsentRecordedAt, isNull);
      expect(customer.utilityConsentRecordedAt, isNull);
      expect(customer.marketingConsentSource, isNull);
      expect(customer.utilityConsentSource, isNull);
    });

    test('Customer serializes and deserializes marketing and utility consent with metadata', () {
      final now = DateTime.now();
      final customer = Customer(
        id: 'cust_consented_1',
        name: 'Pooja Verma',
        phone: '+91 95022 59203',
        hasMarketingConsent: true,
        marketingConsentRecordedAt: now,
        marketingConsentSource: 'Front Desk Digital Tablet',
        marketingConsentEvidence: 'Form #W-2026-001',
        marketingConsentTextVersion: 'v2026.1_festive',
        hasUtilityConsent: true,
        utilityConsentRecordedAt: now,
        utilityConsentSource: 'Online Booking Slip',
        utilityConsentEvidence: 'Booking #BK-9912',
        utilityConsentTextVersion: 'v2026.1_appointment',
      );

      final json = customer.toJson();
      expect(json['hasMarketingConsent'], isTrue);
      expect(json['hasWhatsAppConsent'], isTrue);
      expect(json['hasUtilityConsent'], isTrue);
      expect(json['marketingConsentSource'], 'Front Desk Digital Tablet');
      expect(json['marketingConsentEvidence'], 'Form #W-2026-001');
      expect(json['marketingConsentTextVersion'], 'v2026.1_festive');

      final reconstructed = Customer.fromJson(json);
      expect(reconstructed.id, 'cust_consented_1');
      expect(reconstructed.hasMarketingConsent, isTrue);
      expect(reconstructed.hasUtilityConsent, isTrue);
      expect(reconstructed.hasWhatsAppConsent, isTrue);
      expect(reconstructed.marketingConsentSource, 'Front Desk Digital Tablet');
      expect(reconstructed.marketingConsentEvidence, 'Form #W-2026-001');
      expect(reconstructed.utilityConsentEvidence, 'Booking #BK-9912');
    });

    test('AppRepository recordCustomerConsent updates local state and filters lists correctly', () async {
      SharedPreferences.setMockInitialValues({
        'glowblast_is_initialized_v3': true,
        'glowblast_customers_v3': '[{"id":"cust_test_1","name":"Client 1","phone":"+91 98765 43210","hasMarketingConsent":false,"hasUtilityConsent":false},{"id":"cust_test_2","name":"Client 2","phone":"+91 98765 43211","hasMarketingConsent":false,"hasUtilityConsent":false}]',
      });

      final repository = AppRepository();
      await repository.init();

      expect(repository.marketingConsentedCustomers, isEmpty);
      expect(repository.utilityConsentedCustomers, isEmpty);

      // Record Marketing Consent for Client 1
      await repository.recordCustomerConsent(
        customerId: 'cust_test_1',
        category: 'marketing',
        status: 'opted_in',
        source: 'Front Desk Tablet',
        evidence: 'Signature #4401',
        consentTextVersion: 'v2026.1_promo',
      );

      expect(repository.marketingConsentedCustomers.length, 1);
      expect(repository.marketingConsentedCustomers.first.id, 'cust_test_1');
      expect(repository.marketingConsentedCustomers.first.hasMarketingConsent, isTrue);
      expect(repository.marketingConsentedCustomers.first.hasUtilityConsent, isFalse);
      expect(repository.utilityConsentedCustomers, isEmpty);

      // Record Utility Consent for Client 2
      await repository.recordCustomerConsent(
        customerId: 'cust_test_2',
        category: 'utility',
        status: 'opted_in',
        source: 'Booking Slip',
        evidence: 'Slip #BS-200',
        consentTextVersion: 'v2026.1_utility',
      );

      expect(repository.marketingConsentedCustomers.length, 1);
      expect(repository.utilityConsentedCustomers.length, 1);
      expect(repository.utilityConsentedCustomers.first.id, 'cust_test_2');

      // Opt out Client 1 -> must be immediately excluded from marketing consented list
      await repository.recordCustomerConsent(
        customerId: 'cust_test_1',
        category: 'marketing',
        status: 'opted_out',
        source: 'Customer Request',
        evidence: 'Customer verbal opt-out',
      );

      expect(repository.marketingConsentedCustomers, isEmpty);
      expect(repository.utilityConsentedCustomers.length, 1);
    });
  });
}


