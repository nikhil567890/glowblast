import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:xml/xml.dart';
import '../data/models/customer.dart';

class ExcelParseException implements Exception {
  final String message;
  const ExcelParseException(this.message);

  @override
  String toString() => message;
}

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
      return (v.text ?? v.toString()).trim();
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
    return cellValue.toString().trim();
  }

  static Iterable<XmlElement> _findElementsByLocalName(XmlNode node, String localName) {
    final target = localName.toLowerCase();
    return node.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local.toLowerCase() == target);
  }

  static Iterable<XmlElement> _childElementsByLocalName(XmlElement element, String localName) {
    final target = localName.toLowerCase();
    return element.childElements
        .where((e) => e.name.local.toLowerCase() == target);
  }

  static String? _getAttributeCaseInsensitive(XmlElement element, String attrName) {
    final target = attrName.toLowerCase();
    for (final attr in element.attributes) {
      if (attr.name.local.toLowerCase() == target) {
        return attr.value;
      }
    }
    return null;
  }

  /// Normalizes OpenXML ZIP archive structure before passing to the excel package.
  /// Fixes leading `/xl/` or `xl/` in relationship targets, Windows backslashes in archive paths,
  /// invalid `numFmtId < 164` in styles, and ensures sharedStrings presence.
  static Uint8List normalizeXlsx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final newArchive = Archive();

    bool hasSharedStrings = false;
    ArchiveFile? relsFile;
    ArchiveFile? stylesFile;

    for (final file in archive.files) {
      String cleanName = file.name.replaceAll('\\', '/');
      while (cleanName.startsWith('/')) {
        cleanName = cleanName.substring(1);
      }

      if (cleanName.toLowerCase() == 'xl/sharedstrings.xml') {
        hasSharedStrings = true;
      }
      if (cleanName.toLowerCase() == 'xl/_rels/workbook.xml.rels') {
        relsFile = file;
        continue;
      }
      if (cleanName.toLowerCase() == 'xl/styles.xml') {
        stylesFile = file;
        continue;
      }

      newArchive.addFile(ArchiveFile(cleanName, file.size, file.content));
    }

    // 1. Process workbook.xml.rels
    if (relsFile != null) {
      try {
        final relDoc = XmlDocument.parse(utf8.decode(relsFile.content as List<int>));
        for (final rel in _findElementsByLocalName(relDoc, 'relationship')) {
          var target = _getAttributeCaseInsensitive(rel, 'target') ?? '';
          target = target.replaceAll('\\', '/');
          while (target.startsWith('/')) {
            target = target.substring(1);
          }
          if (target.toLowerCase().startsWith('xl/')) {
            target = target.substring(3);
          }
          rel.setAttribute('Target', target);
        }
        final newXml = utf8.encode(relDoc.toXmlString());
        newArchive.addFile(ArchiveFile('xl/_rels/workbook.xml.rels', newXml.length, newXml));
      } catch (_) {
        newArchive.addFile(ArchiveFile('xl/_rels/workbook.xml.rels', relsFile.size, relsFile.content));
      }
    }

    // 2. Process styles.xml: remove invalid custom numFmt elements where numFmtId < 164
    if (stylesFile != null) {
      try {
        final styleDoc = XmlDocument.parse(utf8.decode(stylesFile.content as List<int>));
        for (final numFmts in _findElementsByLocalName(styleDoc, 'numfmts')) {
          final toRemove = <XmlElement>[];
          for (final numFmt in _childElementsByLocalName(numFmts, 'numfmt')) {
            final idStr = _getAttributeCaseInsensitive(numFmt, 'numfmtid');
            final id = idStr != null ? int.tryParse(idStr) : null;
            if (id != null && id < 164) {
              toRemove.add(numFmt);
            }
          }
          for (final elem in toRemove) {
            elem.parent?.children.remove(elem);
          }
        }
        final newXml = utf8.encode(styleDoc.toXmlString());
        newArchive.addFile(ArchiveFile('xl/styles.xml', newXml.length, newXml));
      } catch (_) {
        newArchive.addFile(ArchiveFile('xl/styles.xml', stylesFile.size, stylesFile.content));
      }
    }

    // 3. Ensure sharedStrings.xml exists
    if (!hasSharedStrings) {
      final defaultSst = utf8.encode(
        '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="0" uniqueCount="0"/>',
      );
      newArchive.addFile(ArchiveFile('xl/sharedStrings.xml', defaultSst.length, defaultSst));
    }

    return Uint8List.fromList(ZipEncoder().encode(newArchive)!);
  }

  /// Directly parses worksheet rows from OpenXML ZIP archive as a fail-safe fallback.
  /// Handles files from Google Sheets, Microsoft Excel, LibreOffice, WPS Office, etc.
  static List<List<String>> parseWorksheetRowsDirectly(Uint8List zipBytes) {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final files = <String, ArchiveFile>{};
    for (final f in archive.files) {
      String name = f.name.replaceAll('\\', '/');
      while (name.startsWith('/')) {
        name = name.substring(1);
      }
      files[name.toLowerCase()] = f;
    }

    final sharedStrings = <String>[];
    final ssFile = files['xl/sharedstrings.xml'];
    if (ssFile != null) {
      try {
        final doc = XmlDocument.parse(utf8.decode(ssFile.content as List<int>));
        for (final si in _findElementsByLocalName(doc, 'si')) {
          final buffer = StringBuffer();
          for (final t in _findElementsByLocalName(si, 't')) {
            buffer.write(t.innerText);
          }
          sharedStrings.add(buffer.toString());
        }
      } catch (_) {}
    }

    // Map relationship IDs to targets from workbook.xml.rels
    final relIdToTarget = <String, String>{};
    final relsFile = files['xl/_rels/workbook.xml.rels'];
    if (relsFile != null) {
      try {
        final relDoc = XmlDocument.parse(utf8.decode(relsFile.content as List<int>));
        for (final rel in _findElementsByLocalName(relDoc, 'relationship')) {
          final id = _getAttributeCaseInsensitive(rel, 'id');
          var target = _getAttributeCaseInsensitive(rel, 'target') ?? '';
          if (id != null && target.isNotEmpty) {
            target = target.replaceAll('\\', '/');
            while (target.startsWith('/')) {
              target = target.substring(1);
            }
            if (!target.toLowerCase().startsWith('xl/')) {
              target = 'xl/$target';
            }
            relIdToTarget[id] = target;
          }
        }
      } catch (_) {}
    }

    // Select worksheet from workbook.xml, preferring Customer-related sheets
    String? sheetPath;
    final wbFile = files['xl/workbook.xml'];
    if (wbFile != null) {
      try {
        final wbDoc = XmlDocument.parse(utf8.decode(wbFile.content as List<int>));
        final sheets = _findElementsByLocalName(wbDoc, 'sheet').toList();
        for (final s in sheets) {
          final name = _getAttributeCaseInsensitive(s, 'name') ?? '';
          final rId = _getAttributeCaseInsensitive(s, 'id') ?? '';
          final lower = name.toLowerCase();
          if (lower == 'customers' || lower == 'customer' || lower == 'clients' || lower == 'contacts') {
            if (relIdToTarget.containsKey(rId)) {
              sheetPath = relIdToTarget[rId];
              break;
            }
          }
        }
        if (sheetPath == null && sheets.isNotEmpty) {
          for (final s in sheets) {
            final rId = _getAttributeCaseInsensitive(s, 'id') ?? '';
            if (relIdToTarget.containsKey(rId)) {
              sheetPath = relIdToTarget[rId];
              break;
            }
          }
        }
      } catch (_) {}
    }

    // Fallback: first worksheet relationship from workbook.xml.rels
    if (sheetPath == null && relsFile != null) {
      try {
        final relDoc = XmlDocument.parse(utf8.decode(relsFile.content as List<int>));
        for (final rel in _findElementsByLocalName(relDoc, 'relationship')) {
          final type = _getAttributeCaseInsensitive(rel, 'type') ?? '';
          if (type.toLowerCase().endsWith('worksheet')) {
            var target = _getAttributeCaseInsensitive(rel, 'target') ?? '';
            target = target.replaceAll('\\', '/');
            while (target.startsWith('/')) {
              target = target.substring(1);
            }
            if (!target.toLowerCase().startsWith('xl/')) {
              target = 'xl/$target';
            }
            sheetPath = target;
            break;
          }
        }
      } catch (_) {}
    }

    sheetPath ??= 'xl/worksheets/sheet1.xml';
    var sheetFile = files[sheetPath.toLowerCase()];
    if (sheetFile == null) {
      for (final entry in files.entries) {
        if (entry.key.startsWith('xl/worksheets/') && entry.key.endsWith('.xml') && !entry.key.contains('_rels')) {
          sheetFile = entry.value;
          break;
        }
      }
    }

    if (sheetFile == null) {
      throw const ExcelParseException('The Excel file contains no worksheets.');
    }

    final sheetDoc = XmlDocument.parse(utf8.decode(sheetFile.content as List<int>));
    final sheetData = _findElementsByLocalName(sheetDoc, 'sheetdata').firstOrNull;
    if (sheetData == null) {
      return [];
    }

    final rows = <List<String>>[];
    for (final rowElem in _childElementsByLocalName(sheetData, 'row')) {
      final cellMap = <int, String>{};
      int maxCol = -1;
      int colCounter = 0;

      for (final c in _childElementsByLocalName(rowElem, 'c')) {
        final rAttr = _getAttributeCaseInsensitive(c, 'r');
        int colIdx = colCounter;
        if (rAttr != null) {
          final colLetters = rAttr.replaceAll(RegExp(r'[^A-Za-z]'), '').toUpperCase();
          if (colLetters.isNotEmpty) {
            int colNum = 0;
            for (int i = 0; i < colLetters.length; i++) {
              colNum = colNum * 26 + (colLetters.codeUnitAt(i) - 64);
            }
            colIdx = colNum - 1;
          }
        }

        final t = _getAttributeCaseInsensitive(c, 't');
        String cellValue = '';

        if (t == 's') {
          final vElem = _childElementsByLocalName(c, 'v').firstOrNull;
          if (vElem != null) {
            final idx = int.tryParse(vElem.innerText.trim());
            if (idx != null && idx >= 0 && idx < sharedStrings.length) {
              cellValue = sharedStrings[idx];
            }
          }
        } else if (t == 'inlineStr') {
          final buffer = StringBuffer();
          for (final tElem in _findElementsByLocalName(c, 't')) {
            buffer.write(tElem.innerText);
          }
          cellValue = buffer.toString();
        } else {
          final vElem = _childElementsByLocalName(c, 'v').firstOrNull;
          if (vElem != null) {
            cellValue = vElem.innerText.trim();
          } else {
            final isElem = _childElementsByLocalName(c, 'is').firstOrNull;
            if (isElem != null) {
              final buffer = StringBuffer();
              for (final tElem in _findElementsByLocalName(isElem, 't')) {
                buffer.write(tElem.innerText);
              }
              cellValue = buffer.toString();
            }
          }
        }

        cellMap[colIdx] = cellValue;
        if (colIdx > maxCol) maxCol = colIdx;
        colCounter = colIdx + 1;
      }

      final rowList = List<String>.filled(maxCol + 1, '');
      for (final entry in cellMap.entries) {
        rowList[entry.key] = entry.value;
      }
      rows.add(rowList);
    }

    return rows;
  }

  /// Extracts rows from Excel file bytes using normalized decoding with direct OpenXML fallback.
  static List<List<String>> _extractRowsFromBytes(Uint8List fileBytes) {
    // 1. Try decoding with Excel package after normalising XML and relationships
    try {
      final normalizedBytes = normalizeXlsx(fileBytes);
      final excel = Excel.decodeBytes(normalizedBytes);
      if (excel.sheets.isNotEmpty) {
        String? targetSheetName;
        for (final key in excel.sheets.keys) {
          final lower = key.toLowerCase();
          if (lower == 'customers' || lower == 'customer' || lower == 'clients' || lower == 'contacts') {
            targetSheetName = key;
            break;
          }
        }
        targetSheetName ??= excel.getDefaultSheet() ?? excel.sheets.keys.first;
        var sheet = excel[targetSheetName];
        if (sheet.rows.isEmpty) {
          for (final entry in excel.sheets.entries) {
            if (entry.value.rows.isNotEmpty) {
              sheet = entry.value;
              break;
            }
          }
        }
        if (sheet.rows.isNotEmpty) {
          final rows = <List<String>>[];
          for (final row in sheet.rows) {
            rows.add(row.map((cell) => extractCellValue(cell?.value).trim()).toList());
          }
          if (rows.isNotEmpty) {
            return rows;
          }
        }
      }
    } catch (_) {
      // If Excel.decodeBytes fails (e.g. TypeError, StateError, etc.), fall through to direct OpenXML parser
    }

    // 2. Fallback: Parse worksheet rows directly from OpenXML ZIP archive
    try {
      return parseWorksheetRowsDirectly(fileBytes);
    } catch (e) {
      if (e is ExcelParseException) rethrow;
      throw ExcelParseException(
        'Could not decode Excel workbook: $e. Ensure the file is a valid .xlsx file and not corrupted.',
      );
    }
  }

  /// Parses Excel file bytes, reads the first sheet, detects columns, validates phone numbers and duplicates
  static ExcelValidationResult parseAndValidate(
    Uint8List fileBytes, {
    List<Customer>? existingCustomers,
  }) {
    if (fileBytes.isEmpty) {
      throw const ExcelParseException('The Excel file is empty.');
    }

    // Check for legacy .xls binary format signature (OLE2 Compound Document: 0xD0, 0xCF, 0x11, 0xE0)
    // — must be checked BEFORE the minimum-size guard so it gives the correct message.
    if (fileBytes.length >= 4 &&
        fileBytes[0] == 0xD0 &&
        fileBytes[1] == 0xCF &&
        fileBytes[2] == 0x11 &&
        fileBytes[3] == 0xE0) {
      throw const ExcelParseException(
        'Legacy .xls format is not supported. Please save or export your spreadsheet as .xlsx (Excel workbook).',
      );
    }

    // A valid .xlsx ZIP file must be at least 22 bytes (minimum valid ZIP end-of-central-directory).
    if (fileBytes.length < 22) {
      throw const ExcelParseException(
        'The Excel file is too small to be valid. It may have been corrupted or incompletely transferred.',
      );
    }

    final rows = _extractRowsFromBytes(fileBytes);

    if (rows.isEmpty) {
      return ExcelValidationResult(
        totalRows: 0,
        validCustomers: [],
        duplicateRows: [],
        invalidPhoneRows: [],
        invalidDataRows: [],
      );
    }

    // Identify header row (check the first 5 rows to allow optional title/banner rows)
    int headerRowIndex = 0;
    int nameIdx = -1;
    int phoneIdx = -1;

    for (int r = 0; r < rows.length && r < 5; r++) {
      final candidateRow = rows[r].map((cell) => cell.trim()).toList();
      int tempName = -1;
      int tempPhone = -1;

      for (int i = 0; i < candidateRow.length; i++) {
        final h = candidateRow[i].toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '');
        if (h == 'name' || h == 'fullname' || h == 'customername' || h == 'clientname') {
          tempName = i;
        } else if (h == 'phone' ||
            h == 'mobile' ||
            h == 'mobilenumber' ||
            h == 'phonenumber' ||
            h == 'contact' ||
            h == 'contactnumber') {
          tempPhone = i;
        }
      }

      if (tempName != -1 && tempPhone != -1) {
        headerRowIndex = r;
        nameIdx = tempName;
        phoneIdx = tempPhone;
        break;
      }
    }

    if (nameIdx == -1 || phoneIdx == -1) {
      final missing = <String>[];
      if (nameIdx == -1) missing.add('"Full Name"');
      if (phoneIdx == -1) missing.add('"Phone Number"');
      throw ExcelParseException(
        'Missing required header(s): ${missing.join(' and ')}. Please ensure your sheet includes "Full Name" and "Phone Number" columns.',
      );
    }

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

    for (int rowIndex = headerRowIndex + 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (row.isEmpty) continue;

      final rawName = (nameIdx >= 0 && nameIdx < row.length)
          ? row[nameIdx].trim()
          : '';
      final rawPhone = (phoneIdx >= 0 && phoneIdx < row.length)
          ? row[phoneIdx].trim()
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
