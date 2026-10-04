import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:glowblast/services/excel_service.dart';
import 'package:glowblast/data/models/settings_model.dart';
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
  });
}
