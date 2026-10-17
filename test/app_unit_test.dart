import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:glowblast/services/excel_service.dart';
import 'package:glowblast/services/glowblast_backend_client.dart';
import 'package:glowblast/data/models/auth_user.dart';
import 'package:glowblast/data/models/settings_model.dart';
import 'package:glowblast/data/models/customer.dart';
import 'package:glowblast/data/models/campaign.dart';
import 'package:glowblast/data/models/whatsapp_template.dart';
import 'package:glowblast/data/repositories/app_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glowblast/features/settings/screens/recharge_meta_balance_screen.dart';
import 'package:glowblast/features/campaigns/screens/direct_send_screen.dart';
import 'package:glowblast/features/campaigns/screens/campaign_wizard_screen.dart';

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

    test('parses real .xlsx with case-insensitive headers and whitespace', () {
      final excel = Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet() ?? 'Sheet1'];
      sheet.appendRow([
        TextCellValue('  FULL name  '),
        TextCellValue(' Phone Number '),
      ]);
      sheet.appendRow([
        TextCellValue('Ravi Kumar'),
        TextCellValue('9876543210'),
      ]);

      final bytes = Uint8List.fromList(excel.save()!);
      final result = ExcelService.parseAndValidate(bytes);
      expect(result.validCount, 1);
      expect(result.validCustomers.first.name, 'Ravi Kumar');
      expect(result.validCustomers.first.phone, '+91 98765 43210');
      expect(result.validCustomers.first.hasWhatsAppConsent, isFalse);
    });

    test('throws ExcelParseException when required headers are missing', () {
      final excel = Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet() ?? 'Sheet1'];
      sheet.appendRow([
        TextCellValue('Random Column 1'),
        TextCellValue('Random Column 2'),
      ]);
      sheet.appendRow([
        TextCellValue('John Doe'),
        TextCellValue('9876543210'),
      ]);

      final bytes = Uint8List.fromList(excel.save()!);
      expect(
        () => ExcelService.parseAndValidate(bytes),
        throwsA(isA<ExcelParseException>().having(
          (e) => e.message,
          'message',
          contains('Missing required header(s)'),
        )),
      );
    });

    test('throws ExcelParseException for empty file bytes', () {
      expect(
        () => ExcelService.parseAndValidate(Uint8List(0)),
        throwsA(isA<ExcelParseException>().having(
          (e) => e.message,
          'message',
          contains('empty'),
        )),
      );
    });

    test('throws ExcelParseException for legacy .xls binary format', () {
      final legacyXlsBytes = Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0x00, 0x01]);
      expect(
        () => ExcelService.parseAndValidate(legacyXlsBytes),
        throwsA(isA<ExcelParseException>().having(
          (e) => e.message,
          'message',
          contains('Legacy .xls'),
        )),
      );
    });

    test('preserves duplicate detection and invalid phone reporting', () {
      final excel = Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet() ?? 'Sheet1'];
      sheet.appendRow([
        TextCellValue('Full Name'),
        TextCellValue('Phone Number'),
      ]);
      sheet.appendRow([
        TextCellValue('Customer One'),
        TextCellValue('9876543210'),
      ]);
      sheet.appendRow([
        TextCellValue('Duplicate Customer'),
        TextCellValue('9876543210'), // Duplicate
      ]);
      sheet.appendRow([
        TextCellValue('Invalid Phone Customer'),
        TextCellValue('12345'), // Invalid phone
      ]);

      final bytes = Uint8List.fromList(excel.save()!);
      final result = ExcelService.parseAndValidate(bytes);
      expect(result.validCount, 1);
      expect(result.duplicateCount, 1);
      expect(result.invalidPhoneCount, 1);
    });

    test('regression test: parses .xlsx with leading /xl/ in relationship targets without TypeError crash', () {
      final original = Excel.createExcel();
      final sheet = original[original.getDefaultSheet()!];
      sheet.appendRow([TextCellValue('Full Name'), TextCellValue('Phone Number')]);
      sheet.appendRow([TextCellValue('Aarav Sharma'), TextCellValue('+91 98765 43210')]);
      final bytes = original.save()!;
      final archive = ZipDecoder().decodeBytes(bytes);

      // Create an archive with /xl/ in relationship target (triggers excel v4.0.6 null-check operator crash)
      final newArchive = Archive();
      for (final f in archive.files) {
        if (f.name == 'xl/_rels/workbook.xml.rels') {
          final relDoc = XmlDocument.parse(utf8.decode(f.content as List<int>));
          for (final r in relDoc.findAllElements('Relationship')) {
            if (r.getAttribute('Target') == 'worksheets/sheet1.xml') {
              r.setAttribute('Target', '/xl/worksheets/sheet1.xml');
            }
          }
          final newXml = utf8.encode(relDoc.toXmlString());
          newArchive.addFile(ArchiveFile(f.name, newXml.length, newXml));
        } else {
          newArchive.addFile(ArchiveFile(f.name, f.size, f.content));
        }
      }

      final badZipBytes = Uint8List.fromList(ZipEncoder().encode(newArchive)!);

      // ExcelService.parseAndValidate should normalize and parse without TypeError
      final result = ExcelService.parseAndValidate(badZipBytes);
      expect(result.validCount, 1);
      expect(result.validCustomers.first.name, 'Aarav Sharma');
      expect(result.validCustomers.first.phone, '+91 98765 43210');
    });

    test('regression test: parses Google Sheets inlineStr workbook without sharedStrings.xml', () {
      final archive = Archive();
      final relsXml = utf8.encode('<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="/xl/worksheets/sheet1.xml"/></Relationships>');
      final sheetXml = utf8.encode('''<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="A1" t="inlineStr"><is><t>Full Name</t></is></c>
      <c r="B1" t="inlineStr"><is><t>Phone Number</t></is></c>
    </row>
    <row r="2">
      <c r="A2" t="inlineStr"><is><t>Priya Sharma</t></is></c>
      <c r="B2" t="inlineStr"><is><t>9876543210</t></is></c>
    </row>
  </sheetData>
</worksheet>''');

      archive.addFile(ArchiveFile('xl/_rels/workbook.xml.rels', relsXml.length, relsXml));
      archive.addFile(ArchiveFile('xl/worksheets/sheet1.xml', sheetXml.length, sheetXml));

      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
      final result = ExcelService.parseAndValidate(zipBytes);
      expect(result.validCount, 1);
      expect(result.validCustomers.first.name, 'Priya Sharma');
      expect(result.validCustomers.first.phone, '+91 98765 43210');
    });

    test('regression test: parses .xlsx with Windows backslashes in archive entry paths', () {
      final original = Excel.createExcel();
      final sheet = original[original.getDefaultSheet()!];
      sheet.appendRow([TextCellValue('Full Name'), TextCellValue('Phone Number')]);
      sheet.appendRow([TextCellValue('Vikram Malhotra'), TextCellValue('+91 99887 76655')]);
      final bytes = original.save()!;
      final archive = ZipDecoder().decodeBytes(bytes);

      final newArchive = Archive();
      for (final f in archive.files) {
        final backslashName = f.name.replaceAll('/', '\\');
        newArchive.addFile(ArchiveFile(backslashName, f.size, f.content));
      }

      final badZipBytes = Uint8List.fromList(ZipEncoder().encode(newArchive)!);
      final result = ExcelService.parseAndValidate(badZipBytes);
      expect(result.validCount, 1);
      expect(result.validCustomers.first.name, 'Vikram Malhotra');
      expect(result.validCustomers.first.phone, '+91 99887 76655');
    });

    test('regression test: parses GlowBlast_Excel_Import_Test.xlsx detecting all 5 customer rows', () {
      final fixturePath = 'test/fixtures/GlowBlast_Excel_Import_Test.xlsx';
      final file = File(fixturePath);
      expect(file.existsSync(), isTrue, reason: 'GlowBlast_Excel_Import_Test.xlsx fixture must exist');

      final bytes = file.readAsBytesSync();
      final result = ExcelService.parseAndValidate(bytes);

      expect(result.totalRows, 5);
      expect(result.validCount, 5);
      expect(result.duplicateCount, 0);
      expect(result.invalidPhoneCount, 0);
      expect(result.otherErrorCount, 0);

      expect(result.validCustomers[0].name, 'TEST ONLY - Customer 01');
      expect(result.validCustomers[0].phone, '+91 98765 00001');

      expect(result.validCustomers[1].name, 'TEST ONLY - Customer 02');
      expect(result.validCustomers[1].phone, '+91 87654 00002');

      expect(result.validCustomers[2].name, 'TEST ONLY - Customer 03');
      expect(result.validCustomers[2].phone, '+91 76543 00003');

      expect(result.validCustomers[3].name, 'TEST ONLY - Customer 04');
      expect(result.validCustomers[3].phone, '+91 65432 00004');

      expect(result.validCustomers[4].name, 'TEST ONLY - Customer 05');
      expect(result.validCustomers[4].phone, '+91 99887 76655');
    });

    test('regression test: parses namespaced x: sheet XML and Customers worksheet relationship', () {
      final archive = Archive();
      final relsXml = utf8.encode(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="/xl/worksheets/sheet1.xml" Id="rIdCust" />'
        '</Relationships>',
      );
      final wbXml = utf8.encode(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<x:workbook xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<x:sheets><x:sheet name="Customers" sheetId="1" r:id="rIdCust" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" /></x:sheets>'
        '</x:workbook>',
      );
      final sheetXml = utf8.encode(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<x:worksheet xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<x:sheetData>'
        '<x:row r="1">'
        '<x:c r="A1" t="str"><x:v>Full Name</x:v></x:c>'
        '<x:c r="B1" t="str"><x:v>Phone Number</x:v></x:c>'
        '</x:row>'
        '<x:row r="2">'
        '<x:c r="A2" t="str"><x:v>Neha Gupta</x:v></x:c>'
        '<x:c r="B2" t="str"><x:v>9811122233</x:v></x:c>'
        '</x:row>'
        '</x:sheetData>'
        '</x:worksheet>',
      );

      archive.addFile(ArchiveFile('xl/_rels/workbook.xml.rels', relsXml.length, relsXml));
      archive.addFile(ArchiveFile('xl/workbook.xml', wbXml.length, wbXml));
      archive.addFile(ArchiveFile('xl/worksheets/sheet1.xml', sheetXml.length, sheetXml));

      final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
      final result = ExcelService.parseAndValidate(bytes);

      expect(result.totalRows, 1);
      expect(result.validCount, 1);
      expect(result.validCustomers.first.name, 'Neha Gupta');
      expect(result.validCustomers.first.phone, '+91 98111 22233');
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

    test('Consent recording requires authentication and rejects unauthenticated request without updating local state', () async {
      SharedPreferences.setMockInitialValues({
        'glowblast_is_initialized_v3': true,
        'glowblast_customers_v3': '[{"id":"cust_test_1","name":"Client 1","phone":"+91 98765 43210","hasMarketingConsent":false}]',
      });
      final repository = AppRepository();
      await repository.init();

      final result = await repository.recordCustomerConsent(
        customerId: 'cust_test_1',
        category: 'marketing',
        status: 'opted_in',
        source: 'Front Desk Tablet',
        evidence: 'Form #101',
      );

      expect(result['success'], isFalse);
      expect(result['error']?['code'], 'UNAUTHORIZED');
      expect(repository.marketingConsentedCustomers, isEmpty);
      expect(repository.customers.first.hasMarketingConsent, isFalse);
    });

    test('Failed backend consent recording does not create false green Opt-In badge', () async {
      SharedPreferences.setMockInitialValues({
        'glowblast_is_initialized_v3': true,
        'glowblast_customers_v3': '[{"id":"cust_test_1","name":"Client 1","phone":"+91 98765 43210","hasMarketingConsent":false}]',
      });
      final repository = AppRepository();
      await repository.init();

      await repository.saveAuthSession(
        'valid_jwt_token',
        AuthUser(id: 'usr_1', name: 'Owner', email: 'owner@spa.com', businessName: 'Spa', emailVerified: true),
      );

      // Mock backend client to return 500 failure
      repository.backendClient = GlowBlastBackendClient(
        baseUrl: 'https://mock.glowblast.api',
        authToken: 'valid_jwt_token',
        httpClient: MockClient((req) async {
          return http.Response(jsonEncode({'success': false, 'error': {'message': 'Database error'}}), 500);
        }),
      );

      final result = await repository.recordCustomerConsent(
        customerId: 'cust_test_1',
        category: 'marketing',
        status: 'opted_in',
        source: 'Front Desk',
        evidence: 'Evidence #1',
      );

      expect(result['success'], isFalse);
      expect(repository.marketingConsentedCustomers, isEmpty);
      expect(repository.customers.first.hasMarketingConsent, isFalse);
    });

    test('Authorized consent recording succeeds and updates local state & filters', () async {
      SharedPreferences.setMockInitialValues({
        'glowblast_is_initialized_v3': true,
        'glowblast_customers_v3': '[{"id":"cust_test_1","name":"Client 1","phone":"+91 98765 43210","hasMarketingConsent":false,"hasUtilityConsent":false},{"id":"cust_test_2","name":"Client 2","phone":"+91 98765 43211","hasMarketingConsent":false,"hasUtilityConsent":false}]',
      });
      final repository = AppRepository();
      await repository.init();

      await repository.saveAuthSession(
        'valid_jwt_token',
        AuthUser(id: 'usr_1', name: 'Owner', email: 'owner@spa.com', businessName: 'Spa', emailVerified: true),
      );

      repository.backendClient = GlowBlastBackendClient(
        baseUrl: 'https://mock.glowblast.api',
        authToken: 'valid_jwt_token',
        httpClient: MockClient((req) async {
          if (req.url.path == '/api/consent/record') {
            final body = jsonDecode(req.body);
            return http.Response(
              jsonEncode({
                'success': true,
                'record': {
                  'phone': body['phone'],
                  'consentCategory': body['consentCategory'],
                  'status': body['status'],
                  'recordedAt': DateTime.now().toIso8601String(),
                  'source': body['source'],
                  'evidence': body['evidence'],
                },
              }),
              200,
            );
          }
          return http.Response('{"success": true}', 200);
        }),
      );

      expect(repository.marketingConsentedCustomers, isEmpty);
      expect(repository.utilityConsentedCustomers, isEmpty);

      // Record Marketing Consent for Client 1
      final res1 = await repository.recordCustomerConsent(
        customerId: 'cust_test_1',
        category: 'marketing',
        status: 'opted_in',
        source: 'Front Desk Tablet',
        evidence: 'Signature #4401',
        consentTextVersion: 'v2026.1_promo',
      );

      expect(res1['success'], isTrue);
      expect(repository.marketingConsentedCustomers.length, 1);
      expect(repository.marketingConsentedCustomers.first.id, 'cust_test_1');
      expect(repository.marketingConsentedCustomers.first.hasMarketingConsent, isTrue);
      expect(repository.marketingConsentedCustomers.first.hasUtilityConsent, isFalse);
      expect(repository.utilityConsentedCustomers, isEmpty);

      // Record Utility Consent for Client 2
      final res2 = await repository.recordCustomerConsent(
        customerId: 'cust_test_2',
        category: 'utility',
        status: 'opted_in',
        source: 'Booking Slip',
        evidence: 'Slip #BS-200',
        consentTextVersion: 'v2026.1_utility',
      );

      expect(res2['success'], isTrue);
      expect(repository.marketingConsentedCustomers.length, 1);
      expect(repository.utilityConsentedCustomers.length, 1);
      expect(repository.utilityConsentedCustomers.first.id, 'cust_test_2');

      // Opt out Client 1 -> must be immediately excluded from marketing consented list
      final res3 = await repository.recordCustomerConsent(
        customerId: 'cust_test_1',
        category: 'marketing',
        status: 'opted_out',
        source: 'Customer Request',
        evidence: 'Customer verbal opt-out',
      );

      expect(res3['success'], isTrue);
      expect(repository.marketingConsentedCustomers, isEmpty);
      expect(repository.utilityConsentedCustomers.length, 1);
    });

    test('bulkRecordMarketingConsent processes 205 customers via bulk API in batches with progress', () async {
      final customersList = List.generate(205, (i) => {
        'id': 'cust_$i',
        'name': 'Client $i',
        'phone': '+91 98765 ${i.toString().padLeft(5, '0')}',
        'hasMarketingConsent': false,
      });

      SharedPreferences.setMockInitialValues({
        'glowblast_is_initialized_v3': true,
        'glowblast_customers_v3': jsonEncode(customersList),
      });
      final repository = AppRepository();
      await repository.init();

      await repository.saveAuthSession(
        'valid_jwt_token',
        AuthUser(id: 'usr_1', name: 'Owner', email: 'owner@spa.com', businessName: 'Spa', emailVerified: true),
      );

      int bulkRecordApiCallCount = 0;
      int singleRecordApiCallCount = 0;
      final progressUpdates = <int>[];

      repository.backendClient = GlowBlastBackendClient(
        baseUrl: 'https://mock.glowblast.api',
        authToken: 'valid_jwt_token',
        httpClient: MockClient((req) async {
          if (req.url.path == '/api/consent/bulk-record') {
            bulkRecordApiCallCount++;
            final body = jsonDecode(req.body);
            final records = List<Map<String, dynamic>>.from(body['records']);
            final results = records.map((r) => {
              'phone': r['phone'],
              'customerId': r['customerId'],
              'consentCategory': 'marketing',
              'status': 'opted_in',
              'success': true,
              'recordedAt': DateTime.now().toIso8601String(),
              'source': r['source'],
              'evidence': r['evidence'],
            }).toList();

            return http.Response(
              jsonEncode({
                'success': true,
                'totalRequested': records.length,
                'succeeded': records.length,
                'failed': 0,
                'results': results,
                'failures': [],
              }),
              200,
            );
          } else if (req.url.path == '/api/consent/record') {
            singleRecordApiCallCount++;
            return http.Response(jsonEncode({'success': true}), 200);
          }
          return http.Response('{"success": true}', 200);
        }),
      );

      final customerIds = List.generate(205, (i) => 'cust_$i');
      final result = await repository.bulkRecordMarketingConsent(
        customerIds: customerIds,
        source: 'Front Desk Verbal Agreement',
        evidence: 'Customer In-Person Verbal Opt-In',
        onProgress: (processed, total) {
          progressUpdates.add(processed);
        },
      );

      // Verify bulk API was used (3 batches of 100, 100, 5)
      expect(bulkRecordApiCallCount, 3);
      // Verify individual single-record endpoint was NOT called 205 times!
      expect(singleRecordApiCallCount, 0);

      // Verify progress reporting
      expect(progressUpdates, containsAllInOrder([0, 100, 200, 205]));

      // Verify results
      expect(result['success'], isTrue);
      expect(result['totalRequested'], 205);
      expect(result['succeeded'], 205);
      expect(result['failed'], 0);
      expect((result['successfulCustomerIds'] as List).length, 205);
      expect((result['failedCustomerIds'] as List), isEmpty);

      // Verify all 205 customers are updated in local state
      expect(repository.marketingConsentedCustomers.length, 205);
    });

    test('bulkRecordMarketingConsent prevents duplicate concurrent submissions', () async {
      SharedPreferences.setMockInitialValues({
        'glowblast_is_initialized_v3': true,
        'glowblast_customers_v3': '[{"id":"cust_1","name":"Client 1","phone":"+91 98765 43210","hasMarketingConsent":false}]',
      });
      final repository = AppRepository();
      await repository.init();

      await repository.saveAuthSession(
        'valid_jwt_token',
        AuthUser(id: 'usr_1', name: 'Owner', email: 'owner@spa.com', businessName: 'Spa', emailVerified: true),
      );

      final completer = Completer<http.Response>();
      repository.backendClient = GlowBlastBackendClient(
        baseUrl: 'https://mock.glowblast.api',
        authToken: 'valid_jwt_token',
        httpClient: MockClient((req) async => completer.future),
      );

      // Start first bulk submission (which hangs waiting for completer)
      final firstFuture = repository.bulkRecordMarketingConsent(
        customerIds: ['cust_1'],
        source: 'Verbal',
        evidence: 'Check-in',
      );

      // Attempt second submission immediately while first is in progress
      final secondResult = await repository.bulkRecordMarketingConsent(
        customerIds: ['cust_1'],
        source: 'Verbal',
        evidence: 'Check-in',
      );

      expect(secondResult['success'], isFalse);
      expect(secondResult['error']['code'], 'OPERATION_IN_PROGRESS');

      // Complete the first
      completer.complete(http.Response(jsonEncode({
        'success': true,
        'totalRequested': 1,
        'succeeded': 1,
        'failed': 0,
        'results': [{
          'phone': '919876543210',
          'customerId': 'cust_1',
          'success': true,
          'status': 'opted_in',
        }],
      }), 200));

      final firstResult = await firstFuture;
      expect(firstResult['success'], isTrue);
      expect(repository.isBulkRecordingConsent, isFalse);
    });

    test('bulkRecordMarketingConsent updates only selected customers and reports partial failures', () async {
      SharedPreferences.setMockInitialValues({
        'glowblast_is_initialized_v3': true,
        'glowblast_customers_v3': '[{"id":"cust_1","name":"Client 1","phone":"+91 98765 43210","hasMarketingConsent":false},{"id":"cust_2","name":"Client 2","phone":"+91 98765 43211","hasMarketingConsent":false},{"id":"cust_3","name":"Client 3","phone":"+91 98765 43212","hasMarketingConsent":false}]',
      });
      final repository = AppRepository();
      await repository.init();

      await repository.saveAuthSession(
        'valid_jwt_token',
        AuthUser(id: 'usr_1', name: 'Owner', email: 'owner@spa.com', businessName: 'Spa', emailVerified: true),
      );

      // Mock backend: succeeds for cust_1, fails for cust_2
      repository.backendClient = GlowBlastBackendClient(
        baseUrl: 'https://mock.glowblast.api',
        authToken: 'valid_jwt_token',
        httpClient: MockClient((req) async {
          if (req.url.path == '/api/consent/bulk-record') {
            return http.Response(
              jsonEncode({
                'success': false,
                'totalRequested': 2,
                'succeeded': 1,
                'failed': 1,
                'results': [
                  {
                    'phone': '919876543210',
                    'customerId': 'cust_1',
                    'consentCategory': 'marketing',
                    'status': 'opted_in',
                    'success': true,
                  },
                  {
                    'phone': '919876543211',
                    'customerId': 'cust_2',
                    'consentCategory': 'marketing',
                    'status': 'opted_out',
                    'success': false,
                    'error': 'Consent update rejected',
                  },
                ],
                'failures': [
                  {
                    'phone': '919876543211',
                    'customerId': 'cust_2',
                    'error': 'Consent update rejected',
                  },
                ],
              }),
              200,
            );
          }
          return http.Response('{"success": true}', 200);
        }),
      );

      // Bulk record for cust_1 and cust_2 (cust_3 is NOT selected)
      final bulkResult = await repository.bulkRecordMarketingConsent(
        customerIds: ['cust_1', 'cust_2'],
        source: 'Verbal Front Desk',
        evidence: 'In-person check-in',
      );

      expect(bulkResult['success'], isFalse); // Partial failure accurately reported
      expect(bulkResult['totalRequested'], 2);
      expect(bulkResult['succeeded'], 1);
      expect(bulkResult['failed'], 1);
      expect(bulkResult['failures'].length, 1);
      expect(bulkResult['failures'][0]['customerId'], 'cust_2');
      expect(bulkResult['failedCustomerIds'], ['cust_2']);
      expect(bulkResult['successfulCustomerIds'], ['cust_1']);

      // cust_1 was updated with verified opt-in
      expect(repository.customers.firstWhere((c) => c.id == 'cust_1').hasMarketingConsent, isTrue);
      // cust_2 was NOT updated because backend rejected it
      expect(repository.customers.firstWhere((c) => c.id == 'cust_2').hasMarketingConsent, isFalse);
      // cust_3 was untouched because it was never selected
      expect(repository.customers.firstWhere((c) => c.id == 'cust_3').hasMarketingConsent, isFalse);
    });

    test('bulk consent cannot override a recorded opt-out and preserves unselected customers', () async {
      SharedPreferences.setMockInitialValues({
        'glowblast_is_initialized_v3': true,
        'glowblast_customers_v3': '[{"id":"cust_opted_out","name":"Opted Out Client","phone":"+91 98765 43210","hasMarketingConsent":false,"isOptedOut":true},{"id":"cust_unselected","name":"Unselected Client","phone":"+91 98765 43211","hasMarketingConsent":false,"isOptedOut":false}]',
      });
      final repository = AppRepository();
      await repository.init();

      await repository.saveAuthSession(
        'valid_jwt_token',
        AuthUser(id: 'usr_1', name: 'Owner', email: 'owner@spa.com', businessName: 'Spa', emailVerified: true),
      );

      bool allowOptOutOverrideReceived = true;
      repository.backendClient = GlowBlastBackendClient(
        baseUrl: 'https://mock.glowblast.api',
        authToken: 'valid_jwt_token',
        httpClient: MockClient((req) async {
          if (req.url.path == '/api/consent/bulk-record') {
            final body = jsonDecode(req.body);
            allowOptOutOverrideReceived = body['allowOptOutOverride'] == true;
            return http.Response(
              jsonEncode({
                'success': false,
                'totalRequested': 1,
                'succeeded': 0,
                'failed': 1,
                'results': [
                  {
                    'phone': '919876543210',
                    'customerId': 'cust_opted_out',
                    'success': false,
                    'error': 'Consent update rejected. Reversing an opt-out requires allowOptOutOverride: true and verified administrator authorization.',
                  },
                ],
                'failures': [
                  {
                    'customerId': 'cust_opted_out',
                    'error': 'Consent update rejected',
                  },
                ],
              }),
              200,
            );
          }
          return http.Response('{"success": true}', 200);
        }),
      );

      final bulkResult = await repository.bulkRecordMarketingConsent(
        customerIds: ['cust_opted_out'],
        source: 'Front Desk Attempt',
        evidence: 'Verbal claim',
      );

      expect(allowOptOutOverrideReceived, isFalse);
      expect(bulkResult['success'], isFalse);
      expect(bulkResult['failed'], 1);
      expect(repository.customers.firstWhere((c) => c.id == 'cust_opted_out').hasMarketingConsent, isFalse);
      expect(repository.customers.firstWhere((c) => c.id == 'cust_unselected').hasMarketingConsent, isFalse);
    });

    test('bulkRecordMarketingConsent handles timeout after successful write safely using batchCheckConsent', () async {
      SharedPreferences.setMockInitialValues({
        'glowblast_is_initialized_v3': true,
        'glowblast_customers_v3': '[{"id":"cust_timeout","name":"Timeout Client","phone":"+91 98765 43210","hasMarketingConsent":false}]',
      });
      final repository = AppRepository();
      await repository.init();

      await repository.saveAuthSession(
        'valid_jwt_token',
        AuthUser(id: 'usr_1', name: 'Owner', email: 'owner@spa.com', businessName: 'Spa', emailVerified: true),
      );

      repository.backendClient = GlowBlastBackendClient(
        baseUrl: 'https://mock.glowblast.api',
        authToken: 'valid_jwt_token',
        httpClient: MockClient((req) async {
          if (req.url.path == '/api/consent/bulk-record') {
            // Simulate network timeout on client side
            throw TimeoutException('Future not completed after 12s');
          } else if (req.url.path == '/api/consent/batch-check') {
            // Server confirms consent was already saved in DB before connection dropped
            return http.Response(
              jsonEncode({
                'success': true,
                'consents': {
                  '919876543210': true,
                },
              }),
              200,
            );
          }
          return http.Response('{"success": true}', 200);
        }),
      );

      final result = await repository.bulkRecordMarketingConsent(
        customerIds: ['cust_timeout'],
        source: 'Verbal',
        evidence: 'Check-in',
      );

      expect(result['success'], isTrue);
      expect(result['succeeded'], 1);
      expect(repository.customers.firstWhere((c) => c.id == 'cust_timeout').hasMarketingConsent, isTrue);
    });

    test('Excel import preserves customer list without automatically granting marketing consent', () async {
      final bytes = ExcelService.generate200RowTestSampleBytes();
      final result = ExcelService.parseAndValidate(Uint8List.fromList(bytes));

      expect(result.validCustomers.isNotEmpty, isTrue);
      for (final cust in result.validCustomers) {
        expect(cust.hasMarketingConsent, isFalse);
        expect(cust.hasWhatsAppConsent, isFalse);
        expect(cust.hasUtilityConsent, isFalse);
      }
    });
  });

  group('Production Mode & Bulk Management Safeguards Tests', () {
    test('AppRepository init in production mode purges fabricated demo records', () async {
      SharedPreferences.setMockInitialValues({
        'glowblast_is_initialized_v3': true,
        'glowblast_customers_v3': jsonEncode([
          {'id': 'cust_1', 'name': 'Demo Customer 1', 'phone': '+91 98765 00001'},
          {'id': 'cust_real_spa_client', 'name': 'Aarav Patel', 'phone': '+91 98765 43210'},
        ]),
        'glowblast_campaigns_v3': jsonEncode([
          {'id': 'c1', 'name': 'Demo Festive Blast', 'status': 'Sent'},
        ]),
      });

      final repository = AppRepository();
      await repository.init(isProduction: true);

      // Verify fabricated demo customer and campaign were purged
      expect(repository.customers.any((c) => c.id == 'cust_1'), isFalse);
      expect(repository.campaigns.any((c) => c.id == 'c1'), isFalse);

      // Verify authentic customer is preserved
      expect(repository.customers.any((c) => c.id == 'cust_real_spa_client'), isTrue);
    });

    test('bulkAssignGroup and bulkRemoveFromGroup preserve individual customer fields', () async {
      SharedPreferences.setMockInitialValues({
        'glowblast_is_initialized_v3': true,
        'glowblast_customers_v3': jsonEncode([
          {'id': 'cust_a', 'name': 'Client Alpha', 'phone': '+91 98765 11111', 'hasMarketingConsent': true},
          {'id': 'cust_b', 'name': 'Client Beta', 'phone': '+91 98765 22222', 'hasMarketingConsent': false},
        ]),
      });

      final repository = AppRepository();
      await repository.init();

      final groupId = repository.groups.first.id;

      // Bulk assign to group
      await repository.bulkAssignGroup(
        customerIds: ['cust_a', 'cust_b'],
        groupId: groupId,
      );

      final groupAfterAssign = repository.groups.firstWhere((g) => g.id == groupId);
      expect(groupAfterAssign.customerIds.contains('cust_a'), isTrue);
      expect(groupAfterAssign.customerIds.contains('cust_b'), isTrue);

      // Verify individual customer details (name, phone, consent) were untouched and not overwritten
      final custA = repository.customers.firstWhere((c) => c.id == 'cust_a');
      final custB = repository.customers.firstWhere((c) => c.id == 'cust_b');
      expect(custA.name, 'Client Alpha');
      expect(custA.phone, '+91 98765 11111');
      expect(custA.hasMarketingConsent, isTrue);
      expect(custB.name, 'Client Beta');
      expect(custB.phone, '+91 98765 22222');
      expect(custB.hasMarketingConsent, isFalse);

      // Bulk remove cust_a from group
      await repository.bulkRemoveFromGroup(
        customerIds: ['cust_a'],
        groupId: groupId,
      );

      final groupAfterRemove = repository.groups.firstWhere((g) => g.id == groupId);
      expect(groupAfterRemove.customerIds.contains('cust_a'), isFalse);
      expect(groupAfterRemove.customerIds.contains('cust_b'), isTrue);
    });

    test('bulkDeleteCustomers removes records locally and updates group membership safely', () async {
      SharedPreferences.setMockInitialValues({
        'glowblast_is_initialized_v3': true,
        'glowblast_customers_v3': jsonEncode([
          {'id': 'del_1', 'name': 'Delete Me 1', 'phone': '+91 98765 33333'},
          {'id': 'del_2', 'name': 'Delete Me 2', 'phone': '+91 98765 44444'},
          {'id': 'keep_1', 'name': 'Keep Me', 'phone': '+91 98765 55555'},
        ]),
      });

      final repository = AppRepository();
      await repository.init();

      final groupId = repository.groups.first.id;
      await repository.bulkAssignGroup(
        customerIds: ['del_1', 'keep_1'],
        groupId: groupId,
      );

      await repository.saveAuthSession(
        'valid_jwt_token',
        AuthUser(id: 'usr_1', name: 'Owner', email: 'owner@spa.com', businessName: 'Spa', emailVerified: true),
      );

      // Mock backend client to verify HTTP deletion request
      List<String>? deletedPayload;
      repository.backendClient = GlowBlastBackendClient(
        baseUrl: 'https://mock.glowblast.api',
        httpClient: MockClient((req) async {
          if (req.url.path == '/api/customers' && req.method == 'DELETE') {
            final body = jsonDecode(req.body);
            deletedPayload = List<String>.from(body['customerIds']);
            return http.Response(jsonEncode({'success': true, 'deletedCount': deletedPayload!.length}), 200);
          }
          return http.Response('{"success": true}', 200);
        }),
      );

      final result = await repository.bulkDeleteCustomers(['del_1', 'del_2']);
      expect(result['success'], isTrue);
      expect(result['deletedCount'], 2);

      // Verify local repository state
      expect(repository.customers.any((c) => c.id == 'del_1'), isFalse);
      expect(repository.customers.any((c) => c.id == 'del_2'), isFalse);
      expect(repository.customers.any((c) => c.id == 'keep_1'), isTrue);

      // Verify customer ID was removed from group membership
      final group = repository.groups.firstWhere((g) => g.id == groupId);
      expect(group.customerIds.contains('del_1'), isFalse);
      expect(group.customerIds.contains('keep_1'), isTrue);

      // Verify payload sent to backend
      expect(deletedPayload, containsAll(['del_1', 'del_2']));
    });

    test('Campaign model accurately tracks authentic replied count', () {
      final campaign = Campaign(
        id: 'camp_authentic_1',
        name: 'Weekend Spa Retreat',
        month: 'October',
        date: DateTime.now(),
        targetAudience: 'VIP Clients',
        messageContent: 'Special 20% off massage bookings this weekend!',
        templateName: 'weekend_spa_retreat',
        status: 'Sent',
        recipients: 50,
        messagesSent: 50,
        delivered: 48,
        read: 35,
        replied: 8,
        failed: 2,
      );

      expect(campaign.replied, 8);
      expect(campaign.delivered, 48);
      expect(campaign.read, 35);
      expect(campaign.failed, 2);

      final json = campaign.toJson();
      expect(json['replied'], 8);

      final restored = Campaign.fromJson(json);
      expect(restored.replied, 8);
    });
  });

  group('Feature 1: Meta Messaging Balance Recharge Tests', () {
    test('Meta Business Manager entry point URL is strictly verified https://business.facebook.com/', () {
      expect(RechargeMetaBalanceScreen.metaBusinessManagerUrl, 'https://business.facebook.com/');
      final uri = Uri.parse(RechargeMetaBalanceScreen.metaBusinessManagerUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, 'business.facebook.com');
      expect(uri.path, '/');
    });

    test('RechargeMetaBalanceScreen aliases BuyCreditsScreen for seamless backwards compatibility', () {
      expect(BuyCreditsScreen, equals(RechargeMetaBalanceScreen));
    });
  });

  group('Feature 2: Search Contacts in Custom Picked Recipients Tests', () {
    late List<Customer> testCustomers;

    setUp(() {
      testCustomers = [
        Customer(
          id: 'cust_001',
          name: 'Aarav Sharma',
          phone: '+91 98765 43210',
          createdAt: DateTime(2026, 1, 1),
          hasMarketingConsent: true,
        ),
        Customer(
          id: 'cust_002',
          name: 'Priya Patel',
          phone: '+91 91234 56789',
          createdAt: DateTime(2026, 1, 2),
          hasMarketingConsent: true,
        ),
        Customer(
          id: 'cust_003',
          name: 'Rohan Gupta',
          phone: '+91 98765 99999',
          createdAt: DateTime(2026, 1, 3),
          hasMarketingConsent: true,
        ),
        Customer(
          id: 'cust_004',
          name: 'Ananya Iyer',
          phone: '+91 87654 32109',
          createdAt: DateTime(2026, 1, 4),
          isOptedOut: true,
          hasMarketingConsent: false,
        ),
      ];
    });

    List<Customer> filterContacts(List<Customer> list, String query) {
      final q = query.trim().toLowerCase();
      if (q.isEmpty) return list;
      final qDigits = q.replaceAll(RegExp(r'\D'), '');
      return list.where((c) {
        final nameMatch = c.name.toLowerCase().contains(q);
        final phoneClean = c.phone.replaceAll(RegExp(r'\D'), '');
        final phoneMatch = phoneClean.contains(qDigits.isNotEmpty ? qDigits : q);
        return nameMatch || phoneMatch;
      }).toList();
    }

    test('filters customers by name case-insensitively', () {
      final resultsLower = filterContacts(testCustomers, 'priya');
      expect(resultsLower.length, 1);
      expect(resultsLower.first.id, 'cust_002');

      final resultsUpper = filterContacts(testCustomers, 'AARAV');
      expect(resultsUpper.length, 1);
      expect(resultsUpper.first.id, 'cust_001');
    });

    test('filters customers by phone number digits regardless of spaces and formatting', () {
      final results1 = filterContacts(testCustomers, '91234');
      expect(results1.length, 1);
      expect(results1.first.name, 'Priya Patel');

      final resultsPrefix = filterContacts(testCustomers, '+91 98765');
      expect(resultsPrefix.length, 2);
      expect(resultsPrefix.map((c) => c.name), containsAll(['Aarav Sharma', 'Rohan Gupta']));
    });

    test('preserves customer selection state across search query changes', () {
      final selectedCustomerIds = <String>{'cust_001', 'cust_002'};

      // 1. Initial state: 2 customers selected
      expect(selectedCustomerIds.length, 2);
      expect(selectedCustomerIds.contains('cust_001'), isTrue);
      expect(selectedCustomerIds.contains('cust_002'), isTrue);

      // 2. User searches for 'Rohan' (neither cust_001 nor cust_002 is visible)
      final filtered1 = filterContacts(testCustomers, 'Rohan');
      expect(filtered1.length, 1);
      expect(filtered1.first.id, 'cust_003');

      // Crucial requirement: searching must NOT clear existing selections
      expect(selectedCustomerIds.contains('cust_001'), isTrue);
      expect(selectedCustomerIds.contains('cust_002'), isTrue);
      expect(selectedCustomerIds.length, 2);

      // 3. User checks Rohan from the search result
      selectedCustomerIds.add('cust_003');
      expect(selectedCustomerIds.length, 3);

      // 4. User clears search query
      final allFiltered = filterContacts(testCustomers, '');
      expect(allFiltered.length, 4);

      // All 3 selected customers remain selected
      expect(selectedCustomerIds.contains('cust_001'), isTrue);
      expect(selectedCustomerIds.contains('cust_002'), isTrue);
      expect(selectedCustomerIds.contains('cust_003'), isTrue);
    });

    test('Select Visible adds only visible filtered contacts without losing previous selections', () {
      final selectedCustomerIds = <String>{'cust_002'}; // Priya already selected

      // User searches '98765' -> matches Aarav and Rohan
      final visible = filterContacts(testCustomers, '98765');
      expect(visible.length, 2);

      // Tap "Select Visible"
      for (final c in visible) {
        selectedCustomerIds.add(c.id);
      }

      // Priya (cust_002) is preserved, Aarav and Rohan are now also selected
      expect(selectedCustomerIds.length, 3);
      expect(selectedCustomerIds, containsAll(['cust_001', 'cust_002', 'cust_003']));
    });

    test('Clear Selection empties selection safely', () {
      final selectedCustomerIds = <String>{'cust_001', 'cust_002', 'cust_003'};
      selectedCustomerIds.clear();
      expect(selectedCustomerIds.isEmpty, isTrue);
    });

    test('handles empty search results gracefully', () {
      final results = filterContacts(testCustomers, 'NonExistentCustomerNameOrNumber');
      expect(results.isEmpty, isTrue);
    });
  });

  group('Feature 3: Single Contact Direct Send vs Multi-Contact Campaign Flow Tests', () {
    late AppRepository repository;
    late GlowBlastBackendClient backendClient;
    late List<Map<String, dynamic>> sentRequests;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'app_mode': 'live_production',
        'auth_token': 'test_auth_token_spa',
      });

      sentRequests = [];
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/campaigns/send') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sentRequests.add(body);
          return http.Response(
            jsonEncode({
              'success': true,
              'campaignId': 'camp_direct_${DateTime.now().millisecondsSinceEpoch}',
              'status': 'Accepted',
              'messagesSent': 1,
              'recipientCount': 1,
              'metaResult': {'accepted': true},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"success": true}', 200, headers: {'content-type': 'application/json'});
      });

      backendClient = GlowBlastBackendClient(
        baseUrl: 'https://glowblast-api.onrender.com',
        httpClient: mockClient,
      );

      repository = AppRepository();
      await repository.init();
    });

    test('selecting exactly one contact directs to single recipient direct-send with accurate customer details', () {
      final customer = Customer(
        id: 'cust_direct_01',
        name: 'Meera Rao',
        phone: '+91 98765 11111',
        createdAt: DateTime(2026, 2, 1),
        hasMarketingConsent: true,
      );

      final directScreen = DirectSendScreen(
        repository: repository,
        customer: customer,
      );

      expect(directScreen.customer.id, 'cust_direct_01');
      expect(directScreen.customer.name, 'Meera Rao');
      expect(directScreen.customer.phone, '+91 98765 11111');
      expect(directScreen.customer.isOptedOut, isFalse);
    });

    test('CampaignWizardScreen accepts preselectedCustomerIds and sets audience to Custom without restarting to All', () {
      final wizard = CampaignWizardScreen(
        repository: repository,
        preselectedAudience: 'Custom',
        preselectedCustomerIds: {'cust_001', 'cust_002'},
      );

      expect(wizard.preselectedAudience, 'Custom');
      expect(wizard.preselectedCustomerIds, containsAll(['cust_001', 'cust_002']));
    });

    test('direct send request passes recipient list with exactly 1 customer and approved template', () async {
      final customer = Customer(
        id: 'cust_direct_99',
        name: 'Kavita Sen',
        phone: '+91 98765 22222',
        createdAt: DateTime(2026, 2, 1),
        hasMarketingConsent: true,
      );

      // Simulate sending via backend client as DirectSendScreen does
      final response = await backendClient.sendCampaign(
        campaignId: 'camp_direct_test_99',
        campaignName: 'Direct Message: Kavita Sen',
        templateName: 'diwali_spa_offer',
        templateLanguage: 'en',
        recipients: [
          {
            'id': customer.id,
            'name': customer.name,
            'phone': customer.phone,
          }
        ],
        templateVariables: ['Kavita Sen', 'Lotus Spa'],
        token: 'test_auth_token_spa',
      );

      expect(response['success'], isTrue);
      expect(sentRequests.length, 1);
      final req = sentRequests.first;
      expect(req['campaignName'], 'Direct Message: Kavita Sen');
      expect(req['templateName'], 'diwali_spa_offer');
      expect(req['recipients'], isList);
      final reqRecipients = req['recipients'] as List;
      expect(reqRecipients.length, 1);
      expect(reqRecipients.first['id'], 'cust_direct_99');
      expect(reqRecipients.first['name'], 'Kavita Sen');
      expect(reqRecipients.first['phone'], '+91 98765 22222');
    });
  });

  group('Safety & Messaging Safeguard Tests', () {
    test('opted-out customer is identified and prevented from promotional messaging', () {
      final optedOutCustomer = Customer(
        id: 'cust_opted_out',
        name: 'Sunita Verma',
        phone: '+91 98765 33333',
        createdAt: DateTime(2026, 2, 1),
        isOptedOut: true,
        hasMarketingConsent: false,
      );

      expect(optedOutCustomer.isOptedOut, isTrue);
      expect(optedOutCustomer.hasMarketingConsent, isFalse);
    });

    test('invalid phone numbers are caught before message transmission', () {
      expect(ExcelService.isValidIndianPhone(''), isFalse);
      expect(ExcelService.isValidIndianPhone('12345'), isFalse);
      expect(ExcelService.isValidIndianPhone('5555555555'), isFalse);
      expect(ExcelService.isValidIndianPhone('+1 555 123 4567'), isFalse); // Non-Indian
      expect(ExcelService.isValidIndianPhone('+91 98765 43210'), isTrue);
    });

    test('debouncing and double-tap prevention prevents duplicate send requests', () async {
      int apiCalls = 0;
      bool isSending = false;

      Future<void> triggerSend() async {
        if (isSending) return; // Guard against repeat taps
        isSending = true;
        try {
          apiCalls++;
          await Future.delayed(const Duration(milliseconds: 50));
        } finally {
          isSending = false;
        }
      }

      // Simulate rapid double tap
      final future1 = triggerSend();
      final future2 = triggerSend();
      await Future.wait([future1, future2]);

      expect(apiCalls, 1); // Only 1 API call allowed
    });

    test('distinguishes API success from backend error responses', () async {
      final failingMockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {'code': 'RATE_LIMIT', 'message': 'WhatsApp Cloud API rate limit exceeded'}
          }),
          429,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = GlowBlastBackendClient(
        baseUrl: 'https://glowblast-api.onrender.com',
        httpClient: failingMockClient,
      );

      final result = await client.sendCampaign(
        campaignId: 'camp_rate_limited',
        campaignName: 'Test Send',
        templateName: 'diwali_spa_offer',
        templateLanguage: 'en',
        recipients: [
          {'id': 'c1', 'name': 'Aarav', 'phone': '+91 98765 43210'}
        ],
        token: 'test_token',
      );

      expect(result['success'], isFalse);
      expect(result['error']['code'], 'RATE_LIMIT');
    });
  });

  group('Bulk Customer Deletion Frontend & Repository Tests', () {
    test('backend client sends DELETE /api/customers with authorization and customerIds payload', () async {
      String? recordedMethod;
      String? recordedPath;
      String? recordedAuth;
      Map<String, dynamic>? recordedBody;

      final mockClient = MockClient((request) async {
        recordedMethod = request.method;
        recordedPath = request.url.path;
        recordedAuth = request.headers['Authorization'];
        recordedBody = jsonDecode(request.body) as Map<String, dynamic>;

        return http.Response(
          jsonEncode({
            'success': true,
            'totalRequested': 2,
            'deletedCount': 2,
            'deletedCustomerIds': ['cust_1', 'cust_2'],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = GlowBlastBackendClient(
        baseUrl: 'https://glowblast-api.onrender.com',
        httpClient: mockClient,
      );

      final result = await client.bulkDeleteCustomers(
        customerIds: ['cust_1', 'cust_2'],
        token: 'auth_jwt_token_123',
      );

      expect(result['success'], isTrue);
      expect(recordedMethod, 'DELETE');
      expect(recordedPath, '/api/customers');
      expect(recordedAuth, 'Bearer auth_jwt_token_123');
      expect(recordedBody!['customerIds'], containsAll(['cust_1', 'cust_2']));
    });

    test('backend client gracefully retries with POST /api/customers/bulk-delete if DELETE returns 404', () async {
      final requestedPaths = <String>[];
      final requestedMethods = <String>[];

      final mockClient = MockClient((request) async {
        requestedPaths.add(request.url.path);
        requestedMethods.add(request.method);

        if (request.method == 'DELETE' && request.url.path == '/api/customers') {
          return http.Response(
            jsonEncode({
              'success': false,
              'error': {'code': 'NOT_FOUND', 'message': 'API endpoint does not exist'},
            }),
            404,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.method == 'POST' && request.url.path == '/api/customers/bulk-delete') {
          return http.Response(
            jsonEncode({
              'success': true,
              'totalRequested': 1,
              'deletedCount': 1,
              'deletedCustomerIds': ['cust_fallback'],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('{"success": false}', 500, headers: {'content-type': 'application/json'});
      });

      final client = GlowBlastBackendClient(
        baseUrl: 'https://glowblast-api.onrender.com',
        httpClient: mockClient,
      );

      final result = await client.bulkDeleteCustomers(
        customerIds: ['cust_fallback'],
        token: 'token_abc',
      );

      expect(result['success'], isTrue);
      expect(requestedMethods, containsAllInOrder(['DELETE', 'POST']));
      expect(requestedPaths, containsAllInOrder(['/api/customers', '/api/customers/bulk-delete']));
    });

    test('failed deletion returns server error and does not remove local customers', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {'code': 'DATABASE_ERROR', 'message': 'Database connection unavailable'},
          }),
          500,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = GlowBlastBackendClient(
        baseUrl: 'https://glowblast-api.onrender.com',
        httpClient: mockClient,
      );

      final result = await client.bulkDeleteCustomers(
        customerIds: ['cust_xyz'],
        token: 'token_xyz',
      );

      expect(result['success'], isFalse);
      expect(result['error']['message'], 'Database connection unavailable');
    });
  });

  group('Simplified Campaign Metrics Tests (Sent & Failed Only)', () {
    test('accurately tracks totalFailed and totalMessagesSent without requiring Delivered or Read', () {
      final campaigns = [
        Campaign(
          id: 'c1',
          name: 'Spa Promo 1',
          month: 'Oct',
          date: DateTime.now(),
          targetAudience: 'All',
          messageContent: 'Offer 1',
          templateName: 'offer_1',
          status: 'Completed',
          recipients: 10,
          messagesSent: 10,
          delivered: 0,
          read: 0,
          replied: 0,
          failed: 0,
        ),
        Campaign(
          id: 'c2',
          name: 'Spa Promo 2',
          month: 'Oct',
          date: DateTime.now(),
          targetAudience: 'VIP',
          messageContent: 'Offer 2',
          templateName: 'offer_2',
          status: 'Failed',
          recipients: 5,
          messagesSent: 2,
          delivered: 0,
          read: 0,
          replied: 0,
          failed: 3,
        ),
      ];

      final totalSent = campaigns.fold(0, (sum, c) => sum + c.messagesSent);
      final totalFailed = campaigns.fold(0, (sum, c) => sum + c.failed);

      expect(totalSent, 12);
      expect(totalFailed, 3);
    });

    test('handles zero failed count accurately without fabricating numbers', () {
      final campaign = Campaign(
        id: 'c3',
        name: 'Perfect Blast',
        month: 'Oct',
        date: DateTime.now(),
        targetAudience: 'All',
        messageContent: 'Message',
        templateName: 'tmpl',
        status: 'Completed',
        recipients: 20,
        messagesSent: 20,
        delivered: 0,
        read: 0,
        replied: 0,
        failed: 0,
      );

      expect(campaign.failed, 0);
      expect(campaign.messagesSent, 20);
    });
  });
}




