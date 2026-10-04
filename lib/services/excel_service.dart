import 'dart:typed_data';
import 'package:excel/excel.dart';
import '../data/models/customer.dart';

class ExcelRowError {
  final int rowNumber;
  final String name;
  final String rawPhone;
  final String errorReason;

  ExcelRowError({
    required this.rowNumber,
    required this.name,
    required this.rawPhone,
    required this.errorReason,
  });
}

class ExcelValidationResult {
  final int totalRows;
  final List<Customer> validCustomers;
  final List<ExcelRowError> duplicateRows;
  final List<ExcelRowError> invalidPhoneRows;
  final List<ExcelRowError> invalidDataRows;

  ExcelValidationResult({
    required this.totalRows,
    required this.validCustomers,
    required this.duplicateRows,
    required this.invalidPhoneRows,
    required this.invalidDataRows,
  });

  int get validCount => validCustomers.length;
  int get duplicateCount => duplicateRows.length;
  int get invalidPhoneCount => invalidPhoneRows.length;
  int get otherErrorCount => invalidDataRows.length;
  int get totalErrors => duplicateCount + invalidPhoneCount + otherErrorCount;
}

class ExcelService {
  /// Extracts clean 10-digit Indian mobile number from any string or number representation
  static String extractClean10Digits(String raw) {
    String clean = raw.replaceAll(RegExp(r'\D'), '');
    if (clean.length == 12 && clean.startsWith('91')) {
      clean = clean.substring(2);
    } else if (clean.length == 11 && clean.startsWith('0')) {
      clean = clean.substring(1);
    }
    return clean;
  }

  /// Checks if phone number is a valid 10-digit Indian mobile (starts with 6, 7, 8, 9)
  static bool isValidIndianPhone(String raw) {
    final digits = extractClean10Digits(raw);
    return digits.length == 10 && RegExp(r'^[6-9]\d{9}$').hasMatch(digits);
  }

  /// Formats phone number into standard "+91 XXXXX XXXXX" text
  static String formatIndianPhone(String raw) {
    final digits = extractClean10Digits(raw);
    if (digits.length == 10) {
      return '+91 ${digits.substring(0, 5)} ${digits.substring(5)}';
    }
    return raw.trim();
  }

  /// Extracts text representation safely from any CellValue type without scientific notation
  static String extractCellValue(CellValue? cellValue) {
    if (cellValue == null) return '';
    if (cellValue is TextCellValue) {
      final v = cellValue.value;
      return v.text ?? v.toString();
    } else if (cellValue is IntCellValue) {
      return cellValue.value.toString();
    } else if (cellValue is DoubleCellValue) {
      final d = cellValue.value;
      if (d % 1 == 0) {
        return d.toInt().toString();
      }
      return d.toStringAsFixed(0);
    } else if (cellValue is DateCellValue) {
      return cellValue.toString();
    } else if (cellValue is BoolCellValue) {
      return cellValue.value.toString();
    }
    return cellValue.toString();
  }

  /// Parses Excel file bytes, reads the first sheet, detects columns, validates phone numbers and duplicates
  static ExcelValidationResult parseAndValidate(
    Uint8List fileBytes, {
    List<Customer>? existingCustomers,
  }) {
    final excel = Excel.decodeBytes(fileBytes);
    if (excel.tables.isEmpty) {
      return ExcelValidationResult(
        totalRows: 0,
        validCustomers: [],
        duplicateRows: [],
        invalidPhoneRows: [],
        invalidDataRows: [],
      );
    }

    final firstSheetName = excel.tables.keys.first;
    final sheet = excel.tables[firstSheetName];
    if (sheet == null || sheet.rows.isEmpty) {
      return ExcelValidationResult(
        totalRows: 0,
        validCustomers: [],
        duplicateRows: [],
        invalidPhoneRows: [],
        invalidDataRows: [],
      );
    }

    // Identify header row
    final headerRow = sheet.rows.first.map((cell) => extractCellValue(cell?.value).trim()).toList();
    int nameIdx = -1;
    int phoneIdx = -1;

    for (int i = 0; i < headerRow.length; i++) {
      final h = headerRow[i].toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '');
      if (h == 'name' || h == 'fullname' || h == 'customername' || h == 'clientname') {
        nameIdx = i;
      } else if (h == 'phone' ||
          h == 'mobile' ||
          h == 'mobilenumber' ||
          h == 'phonenumber' ||
          h == 'contact' ||
          h == 'contactnumber') {
        phoneIdx = i;
      }
    }

    // Column index fallbacks if standard header names were omitted
    if (nameIdx == -1 && headerRow.isNotEmpty) nameIdx = 0;
    if (phoneIdx == -1 && headerRow.length > 1) phoneIdx = 1;

    final existingPhoneSet = <String>{};
    if (existingCustomers != null) {
      for (final c in existingCustomers) {
        final digits = extractClean10Digits(c.phone);
        if (digits.isNotEmpty) existingPhoneSet.add(digits);
      }
    }

    final seenInFilePhones = <String>{};
    final validCustomers = <Customer>[];
    final duplicateRows = <ExcelRowError>[];
    final invalidPhoneRows = <ExcelRowError>[];
    final invalidDataRows = <ExcelRowError>[];

    int processedDataRows = 0;

    for (int rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
      final row = sheet.rows[rowIndex];
      if (row.isEmpty) continue;

      final rawName = (nameIdx >= 0 && nameIdx < row.length)
          ? extractCellValue(row[nameIdx]?.value).trim()
          : '';
      final rawPhone = (phoneIdx >= 0 && phoneIdx < row.length)
          ? extractCellValue(row[phoneIdx]?.value).trim()
          : '';

      // Skip completely empty rows
      if (rawName.isEmpty && rawPhone.isEmpty) {
        continue;
      }

      processedDataRows++;
      final rowDisplayNum = rowIndex + 1;

      if (rawName.isEmpty) {
        invalidDataRows.add(
          ExcelRowError(
            rowNumber: rowDisplayNum,
            name: '(Empty Name)',
            rawPhone: rawPhone,
            errorReason: 'Customer name is required',
          ),
        );
        continue;
      }

      if (rawPhone.isEmpty || !isValidIndianPhone(rawPhone)) {
        invalidPhoneRows.add(
          ExcelRowError(
            rowNumber: rowDisplayNum,
            name: rawName,
            rawPhone: rawPhone.isEmpty ? '(Empty)' : rawPhone,
            errorReason: rawPhone.isEmpty
                ? 'Phone number is missing'
                : 'Invalid 10-digit Indian phone (must start with 6, 7, 8, 9)',
          ),
        );
        continue;
      }

      final digits = extractClean10Digits(rawPhone);

      // Duplicate check: already in app
      if (existingPhoneSet.contains(digits)) {
        duplicateRows.add(
          ExcelRowError(
            rowNumber: rowDisplayNum,
            name: rawName,
            rawPhone: rawPhone,
            errorReason: 'Already exists in your customer directory',
          ),
        );
        continue;
      }

      // Duplicate check: repeated inside the spreadsheet
      if (seenInFilePhones.contains(digits)) {
        duplicateRows.add(
          ExcelRowError(
            rowNumber: rowDisplayNum,
            name: rawName,
            rawPhone: rawPhone,
            errorReason: 'Repeated phone number in this file',
          ),
        );
        continue;
      }

      seenInFilePhones.add(digits);
      validCustomers.add(
        Customer(
          id: 'cust_${DateTime.now().millisecondsSinceEpoch}_$processedDataRows',
          name: rawName,
          phone: formatIndianPhone(digits),
          isOptedOut: false,
        ),
      );
    }

    return ExcelValidationResult(
      totalRows: processedDataRows,
      validCustomers: validCustomers,
      duplicateRows: duplicateRows,
      invalidPhoneRows: invalidPhoneRows,
      invalidDataRows: invalidDataRows,
    );
  }

  /// Exports customer list to Excel workbook bytes (2 columns: Full Name, Phone Number)
  static List<int> exportCustomersToExcelBytes(List<Customer> customers) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[defaultSheet];

    // Header row
    sheet.appendRow([
      TextCellValue('Full Name'),
      TextCellValue('Phone Number'),
    ]);

    for (final customer in customers) {
      sheet.appendRow([
        TextCellValue(customer.name),
        TextCellValue(customer.phone),
      ]);
    }

    return excel.save() ?? [];
  }

  /// Generates the sample Excel template bytes (GlowBlast_Customers_Template.xlsx)
  static List<int> generateSampleTemplateBytes() {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[defaultSheet];

    sheet.appendRow([
      TextCellValue('Full Name'),
      TextCellValue('Phone Number'),
    ]);

    final sampleRows = [
      ['Aarav Sharma', '+91 98765 43210'],
      ['Sneha Nair', '9876500002'],
      ['Rohan Kapoor', '+91-98765-00003'],
      ['Ananya Iyer', '9876500004'],
    ];

    for (final row in sampleRows) {
      sheet.appendRow([
        TextCellValue(row[0]),
        TextCellValue(row[1]),
      ]);
    }

    return excel.save() ?? [];
  }

  /// Generates the 200-row test dataset (sample_customers.xlsx)
  /// Exactly 200 rows: 190 valid unique, 7 duplicates, 3 invalid phone numbers.
  /// Includes both text and numeric phone cells.
  static List<int> generate200RowTestSampleBytes() {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[defaultSheet];

    sheet.appendRow([
      TextCellValue('Full Name'),
      TextCellValue('Phone Number'),
    ]);

    final firstNames = [
      'Aarav', 'Vivaan', 'Aditya', 'Vihaan', 'Arjun', 'Sai', 'Reyansh', 'Ayaan', 'Krishna', 'Ishaan',
      'Shaurya', 'Atharv', 'Advik', 'Pranav', 'Advaith', 'Aaryav', 'Dhruv', 'Kabir', 'Rohan', 'Kian',
      'Priya', 'Ananya', 'Diya', 'Saanvi', 'Aadhya', 'Pari', 'Isha', 'Navya', 'Riya', 'Myra',
      'Anika', 'Aarohi', 'Sara', 'Ahana', 'Avni', 'Tara', 'Anvi', 'Khushi', 'Shanaya', 'Sneha'
    ];

    final lastNames = [
      'Sharma', 'Verma', 'Iyer', 'Patel', 'Nair', 'Mehta', 'Singhania', 'Desai', 'Joshi', 'Rao',
      'Reddy', 'Gupta', 'Kapoor', 'Malhotra', 'Bhatia', 'Chopra', 'Saxena', 'Mukherjee', 'Menon', 'Patil'
    ];

    // Generate 190 valid customers
    for (int i = 0; i < 190; i++) {
      final fname = firstNames[i % firstNames.length];
      final lname = lastNames[(i * 3 + 5) % lastNames.length];
      final name = '$fname $lname';
      final phoneNum = 9810000000 + i;

      // Mix text and numeric cells
      if (i % 2 == 0) {
        sheet.appendRow([
          TextCellValue(name),
          IntCellValue(phoneNum),
        ]);
      } else {
        sheet.appendRow([
          TextCellValue(name),
          TextCellValue('+91 $phoneNum'),
        ]);
      }
    }

    // 7 Duplicate rows (re-using previous valid phone numbers)
    for (int d = 0; d < 7; d++) {
      final name = 'Duplicate Client ${d + 1}';
      final duplicatePhone = 9810000000 + (d * 5); // matches one of the earlier generated phones
      sheet.appendRow([
        TextCellValue(name),
        TextCellValue('+91 $duplicatePhone'),
      ]);
    }

    // 3 Invalid Phone Rows
    sheet.appendRow([
      TextCellValue('Rajesh Invalid 1'),
      TextCellValue('98765'), // Only 5 digits (invalid)
    ]);
    sheet.appendRow([
      TextCellValue('Meera Invalid 2'),
      TextCellValue('NOT_A_PHONE'), // Alphabetic text (invalid)
    ]);
    sheet.appendRow([
      TextCellValue('Suresh Invalid 3'),
      TextCellValue('+91 2234567890'), // Starts with 2 (invalid Indian mobile prefix)
    ]);

    return excel.save() ?? [];
  }
}
