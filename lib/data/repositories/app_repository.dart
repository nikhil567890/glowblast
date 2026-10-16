import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/customer.dart';
import '../models/campaign.dart';
import '../models/group.dart';
import '../models/settings_model.dart';
import '../models/whatsapp_template.dart';
import '../models/auth_user.dart';
import '../demo_data/initial_data.dart';
import '../../services/excel_service.dart';
import '../../services/glowblast_backend_client.dart';

class AppRepository extends ChangeNotifier {
  static const String _keyCustomers = 'glowblast_customers_v3';
  static const String _keyCampaigns = 'glowblast_campaigns_v3';
  static const String _keyGroups = 'glowblast_groups_v3';
  static const String _keyTemplates = 'glowblast_templates_v3';
  static const String _keySettings = 'glowblast_settings_v3';
  static const String _keyInitializedV3 = 'glowblast_is_initialized_v3';
  static const String _keyAuthToken = 'glowblast_auth_token_v1';
  static const String _keyAuthUser = 'glowblast_auth_user_v1';

  List<Customer> _customers = [];
  List<Campaign> _campaigns = [];
  List<CustomerGroup> _groups = [];
  List<WhatsAppTemplate> _templates = [];
  AppSettings _settings = AppSettings();
  String? _authToken;
  AuthUser? _currentUser;
  bool _isLoading = true;
  bool _isBulkRecordingConsent = false;
  late GlowBlastBackendClient backendClient = GlowBlastBackendClient(baseUrl: _settings.backendUrl);

  // Auth getters
  bool get isAuthenticated => _authToken != null && _currentUser != null;
  bool get isBulkRecordingConsent => _isBulkRecordingConsent;
  bool get hasProfile => _settings.hasProfile;
  AuthUser? get currentUser => _currentUser;
  String? get authToken => _authToken;

  // Getters
  List<Customer> get customers => List.unmodifiable(_customers);
  List<Customer> get marketingConsentedCustomers =>
      _customers.where((c) => !c.isOptedOut && c.hasMarketingConsent).toList();
  List<Customer> get utilityConsentedCustomers =>
      _customers.where((c) => !c.isOptedOut && c.hasUtilityConsent).toList();
  List<Customer> get consentedCustomers => marketingConsentedCustomers;
  List<Campaign> get campaigns => List.unmodifiable(_campaigns);
  List<Campaign> get sentCampaigns => _campaigns.where((c) {
    final s = c.status.toLowerCase();
    return s == 'sent' || s == 'accepted' || s == 'completed' || s == 'completed with errors';
  }).toList();
  List<Campaign> get scheduledCampaigns => _campaigns.where((c) => c.status == 'Scheduled').toList();


  List<Campaign> get realTestCampaigns => _campaigns.where((c) => c.isRealTest).toList();
  List<Campaign> get demoCampaigns => _campaigns.where((c) => !c.isRealTest).toList();
  List<CustomerGroup> get groups => List.unmodifiable(_groups);
  List<WhatsAppTemplate> get templates => List.unmodifiable(_templates);
  List<WhatsAppTemplate> get approvedTemplates => _templates.where((t) => t.isApproved).toList();

  /// Returns templates matching the active messaging mode (Production vs Developer Test vs Demo)
  List<WhatsAppTemplate> get activeTemplates {
    if (_settings.isWhatsAppProductionMode) {
      final prodList = _templates.where((t) => t.mode == 'production').toList();
      return List.unmodifiable(prodList);
    } else if (_settings.isWhatsAppTestMode) {
      final testList = _templates.where((t) => t.mode == 'test' || t.mode == 'all').toList();
      return List.unmodifiable(testList.isNotEmpty ? testList : _templates);
    }
    return List.unmodifiable(_templates);
  }

  /// Returns approved templates matching the active messaging mode
  List<WhatsAppTemplate> get activeApprovedTemplates =>
      activeTemplates.where((t) => t.isApproved).toList();

  WhatsAppTemplate? getTemplateById(String id) {
    try {
      return _templates.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  WhatsAppTemplate? getTemplateByName(String name, {String? mode}) {
    final targetMode = mode ?? (_settings.isWhatsAppProductionMode ? 'production' : (_settings.isWhatsAppTestMode ? 'test' : null));
    if (targetMode == 'production') {
      try {
        return _templates.firstWhere(
          (t) => t.name.toLowerCase() == name.toLowerCase() && t.mode == 'production',
        );
      } catch (_) {
        return null;
      }
    } else if (targetMode != null) {
      try {
        return _templates.firstWhere(
          (t) => t.name.toLowerCase() == name.toLowerCase() && (t.mode == targetMode || t.mode == 'all'),
        );
      } catch (_) {
        return null;
      }
    }
    try {
      return _templates.firstWhere((t) => t.name.toLowerCase() == name.toLowerCase());
    } catch (_) {
      return null;
    }
  }

  AppSettings get settings => _settings;
  bool get isLoading => _isLoading;

  // Audience Segments
  List<Customer> get eligibleCustomers => _customers.where((c) => !c.isOptedOut).toList();
  List<Customer> get optedOutCustomers => _customers.where((c) => c.isOptedOut).toList();
  List<Customer> get recentlyAddedCustomers {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    return _customers.where((c) => c.createdAt.isAfter(cutoff) && !c.isOptedOut).toList();
  }

  // Dynamic KPIs derived strictly from stored data
  int get totalCustomersCount => _customers.length;
  int get eligibleCustomersCount => eligibleCustomers.length;
  int get optedOutCustomersCount => optedOutCustomers.length;

  int get totalMessagesSent {
    return sentCampaigns.fold(0, (sum, c) => sum + c.messagesSent);
  }

  int get totalDelivered {
    return sentCampaigns.fold(0, (sum, c) => sum + c.delivered);
  }

  int get totalRead {
    return sentCampaigns.fold(0, (sum, c) => sum + c.read);
  }

  int get totalReplied {
    return sentCampaigns.fold(0, (sum, c) => sum + c.replied);
  }

  int get totalFailed {
    return sentCampaigns.fold(0, (sum, c) => sum + c.failed);
  }

  double get overallDeliveryRate {
    if (totalMessagesSent == 0) return 0.0;
    return (totalDelivered / totalMessagesSent) * 100;
  }

  double get overallReadRate {
    if (totalDelivered == 0) return 0.0;
    return (totalRead / totalDelivered) * 100;
  }

  int get messagesSentThisMonth {
    final now = DateTime.now();
    final thisMonthCampaigns = sentCampaigns.where(
      (c) => c.date.year == now.year && c.date.month == now.month,
    );
    final count = thisMonthCampaigns.fold(0, (sum, c) => sum + c.messagesSent);
    // If none recorded for current calendar month yet, return total sent from active campaigns
    return count > 0 ? count : totalMessagesSent;
  }

  Campaign? get bestPerformingCampaign {
    if (sentCampaigns.isEmpty) return null;
    return sentCampaigns.reduce((a, b) => a.read > b.read ? a : b);
  }

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final isInitialized = prefs.getBool(_keyInitializedV3) ?? false;

      if (!isInitialized) {
        await _seedInitialData(prefs);
      } else {
        await _loadFromPrefs(prefs);
      }
    } catch (e) {
      debugPrint('Error loading local data: $e');
      _fallbackToMemory();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _seedInitialData(SharedPreferences prefs) async {
    // Migration: clean up legacy keys
    await prefs.remove('glowblast_customers');
    await prefs.remove('glowblast_campaigns');
    await prefs.remove('glowblast_groups');
    await prefs.remove('glowblast_automations');
    await prefs.remove('glowblast_settings');
    await prefs.remove('glowblast_is_initialized_v2');

    _customers = InitialData.generate200Customers();
    _campaigns = [
      ...InitialData.getPreloadedCampaigns(),
      ...InitialData.getScheduledCampaigns(),
    ];
    _groups = InitialData.getInitialGroups(_customers);
    _templates = InitialData.getInitialTemplates();
    _settings = AppSettings();
    backendClient = GlowBlastBackendClient(baseUrl: _settings.backendUrl);

    await _saveAll(prefs);
    await prefs.setBool(_keyInitializedV3, true);
  }

  Future<void> _loadFromPrefs(SharedPreferences prefs) async {
    // Customers
    final custRaw = prefs.getString(_keyCustomers);
    if (custRaw != null) {
      final List<dynamic> list = jsonDecode(custRaw);
      _customers = list.map((e) => Customer.fromJson(e as Map<String, dynamic>)).toList();
    } else {
      _customers = InitialData.generate200Customers();
    }

    // Campaigns
    final campRaw = prefs.getString(_keyCampaigns);
    if (campRaw != null) {
      final List<dynamic> list = jsonDecode(campRaw);
      _campaigns = list.map((e) => Campaign.fromJson(e as Map<String, dynamic>)).toList();
    } else {
      _campaigns = [
        ...InitialData.getPreloadedCampaigns(),
        ...InitialData.getScheduledCampaigns(),
      ];
    }

    // Groups
    final grpRaw = prefs.getString(_keyGroups);
    if (grpRaw != null) {
      final List<dynamic> list = jsonDecode(grpRaw);
      _groups = list.map((e) => CustomerGroup.fromJson(e as Map<String, dynamic>)).toList();
    } else {
      _groups = InitialData.getInitialGroups(_customers);
    }

    // Templates
    final tplRaw = prefs.getString(_keyTemplates);
    if (tplRaw != null) {
      try {
        final List<dynamic> list = jsonDecode(tplRaw);
        _templates = list.map((e) => WhatsAppTemplate.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {
        _templates = InitialData.getInitialTemplates();
      }
    } else {
      _templates = InitialData.getInitialTemplates();
    }

    // Settings & Automatic Stale URL Migration
    final setRaw = prefs.getString(_keySettings);
    if (setRaw != null) {
      final map = jsonDecode(setRaw) as Map<String, dynamic>;
      _settings = AppSettings.fromJson(map);
      // If migration replaced an old 10.0.2.2 or localhost URL, persist immediately
      if (map['backendUrl'] != _settings.backendUrl) {
        debugPrint('[AppRepository] Migrated backendUrl from "${map['backendUrl']}" to "${_settings.backendUrl}"');
        await prefs.setString(_keySettings, jsonEncode(_settings.toJson()));
      }
    } else {
      _settings = AppSettings();
    }

    // Load persisted auth session
    _authToken = prefs.getString(_keyAuthToken);
    final userRaw = prefs.getString(_keyAuthUser);
    if (userRaw != null) {
      try {
        _currentUser = AuthUser.fromJson(jsonDecode(userRaw) as Map<String, dynamic>);
      } catch (_) {
        _currentUser = null;
      }
    }

    // Always re-sync backendClient with active settings and persisted token
    backendClient = GlowBlastBackendClient(
      baseUrl: _settings.backendUrl,
      authToken: _authToken,
    );

    // Ensure authorized Meta test recipient is in directory
    final hasTester = _customers.any((c) =>
      c.phone.replaceAll(RegExp(r'\D'), '').endsWith('9182769155')
    );
    if (!hasTester) {
      final insertIndex = 12 < _customers.length ? 12 : 0;
      _customers.insert(
        insertIndex,
        Customer(
          id: 'cust_meta_tester',
          name: 'Authorized Meta Tester',
          phone: '+91 91827 69155',
          isOptedOut: false,
        ),
      );
    }
  }

  /// Securely saves authenticated session and user profile.
  Future<void> saveAuthSession(String token, AuthUser user) async {
    _authToken = token;
    _currentUser = user;
    backendClient.authToken = token;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAuthToken, token);
    await prefs.setString(_keyAuthUser, jsonEncode(user.toJson()));
  }

  /// Clears active authenticated session on logout without wiping business data.
  Future<void> clearAuthSession() async {
    _authToken = null;
    _currentUser = null;
    backendClient.authToken = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAuthToken);
    await prefs.remove(_keyAuthUser);
  }

  void _fallbackToMemory() {
    _customers = InitialData.generate200Customers();
    _campaigns = [
      ...InitialData.getPreloadedCampaigns(),
      ...InitialData.getScheduledCampaigns(),
    ];
    _groups = InitialData.getInitialGroups(_customers);
    _templates = InitialData.getInitialTemplates();
    _settings = AppSettings();
    backendClient = GlowBlastBackendClient(baseUrl: _settings.backendUrl, authToken: _authToken);
  }

  Future<void> _saveAll([SharedPreferences? prefs]) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    await p.setString(_keyCustomers, jsonEncode(_customers.map((c) => c.toJson()).toList()));
    await p.setString(_keyCampaigns, jsonEncode(_campaigns.map((c) => c.toJson()).toList()));
    await p.setString(_keyGroups, jsonEncode(_groups.map((g) => g.toJson()).toList()));
    await p.setString(_keyTemplates, jsonEncode(_templates.map((t) => t.toJson()).toList()));
    await p.setString(_keySettings, jsonEncode(_settings.toJson()));
  }

  // --- Customer Operations ---
  Future<void> addCustomer(Customer customer) async {
    _customers.insert(0, customer);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCustomers, jsonEncode(_customers.map((c) => c.toJson()).toList()));
  }

  Future<void> updateCustomer(Customer customer) async {
    final index = _customers.indexWhere((c) => c.id == customer.id);
    if (index != -1) {
      _customers[index] = customer;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCustomers, jsonEncode(_customers.map((c) => c.toJson()).toList()));
    }
  }

  Future<void> deleteCustomer(String id) async {
    _customers.removeWhere((c) => c.id == id);
    for (final group in _groups) {
      group.customerIds.remove(id);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCustomers, jsonEncode(_customers.map((c) => c.toJson()).toList()));
    await prefs.setString(_keyGroups, jsonEncode(_groups.map((g) => g.toJson()).toList()));
  }

  Future<void> toggleOptOut(String customerId, bool isOptedOut) async {
    final index = _customers.indexWhere((c) => c.id == customerId);
    if (index != -1) {
      _customers[index] = _customers[index].copyWith(isOptedOut: isOptedOut);
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCustomers, jsonEncode(_customers.map((c) => c.toJson()).toList()));
    }
  }

  /// Records genuine, auditable WhatsApp customer opt-in or opt-out consent with category.
  /// Local state is updated ONLY after the backend confirms success.
  /// If the backend call fails (auth error, network, etc.), local state is NOT changed.
  Future<Map<String, dynamic>> recordCustomerConsent({
    required String customerId,
    required String category, // 'marketing' | 'utility'
    required String status,   // 'opted_in' | 'opted_out' | 'revoked'
    required String source,
    required String evidence,
    String? consentTextVersion,
    bool allowOptOutOverride = false,
  }) async {
    final index = _customers.indexWhere((c) => c.id == customerId);
    if (index == -1) {
      return {'success': false, 'error': {'message': 'Customer not found'}};
    }

    // Require authentication before attempting any consent change.
    if (_authToken == null || _authToken!.trim().isEmpty) {
      return {
        'success': false,
        'error': {
          'code': 'UNAUTHORIZED',
          'message': 'You must be logged in to record consent. Please sign in and try again.',
        },
      };
    }

    final customer = _customers[index];
    final cleanPhone = ExcelService.extractClean10Digits(customer.phone);
    final now = DateTime.now();
    final isOptedIn = status == 'opted_in';

    // 1. Post to backend — do NOT update local state until the backend confirms success.
    Map<String, dynamic> backendResult;
    try {
      backendResult = await backendClient.recordConsent(
        phone: cleanPhone.length == 10 ? '91$cleanPhone' : cleanPhone,
        customerId: customer.id,
        consentCategory: category,
        status: status,
        source: source,
        evidence: evidence,
        consentTextVersion: consentTextVersion,
        allowOptOutOverride: allowOptOutOverride,
      );
    } catch (e) {
      debugPrint('[AppRepository] recordCustomerConsent network error: $e');
      return {
        'success': false,
        'error': {
          'code': 'NETWORK_ERROR',
          'message': 'Could not reach the server. Please check your connection and try again.',
        },
      };
    }

    // 2. Only update local state if backend confirmed success.
    final isSuccess = backendResult['success'] == true;
    if (!isSuccess) {
      // Reload authoritative state from backend to discard any stale cached value.
      await _reloadConsentForCustomer(customer, index);
      return backendResult;
    }

    // 3. Update local state from confirmed backend result.
    Customer updatedCustomer;
    if (category == 'utility') {
      updatedCustomer = customer.copyWith(
        hasUtilityConsent: isOptedIn,
        utilityConsentRecordedAt: isOptedIn ? now : null,
        utilityConsentSource: isOptedIn ? source : null,
        utilityConsentEvidence: isOptedIn ? evidence : null,
        utilityConsentTextVersion: isOptedIn ? consentTextVersion : null,
      );
    } else {
      updatedCustomer = customer.copyWith(
        hasMarketingConsent: isOptedIn,
        marketingConsentRecordedAt: isOptedIn ? now : null,
        marketingConsentSource: isOptedIn ? source : null,
        marketingConsentEvidence: isOptedIn ? evidence : null,
        marketingConsentTextVersion: isOptedIn ? consentTextVersion : null,
        isOptedOut: status == 'opted_out' ? true : customer.isOptedOut,
      );
    }

    _customers[index] = updatedCustomer;
    notifyListeners();

    // 4. Persist confirmed state to SharedPreferences.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCustomers, jsonEncode(_customers.map((c) => c.toJson()).toList()));

    return backendResult;
  }

  /// Reloads authoritative marketing consent state from backend for a single customer.
  /// Called after a failed consent write to discard any stale cached state.
  Future<void> _reloadConsentForCustomer(Customer customer, int index) async {
    try {
      final cleanPhone = ExcelService.extractClean10Digits(customer.phone);
      final phone = cleanPhone.length == 10 ? '91$cleanPhone' : cleanPhone;
      final result = await backendClient.getConsent(phone: phone, category: 'marketing');
      if (result['success'] == true) {
        final hasConsent = result['hasConsent'] == true;
        final record = result['record'] as Map<String, dynamic>?;
        _customers[index] = customer.copyWith(
          hasMarketingConsent: hasConsent,
          marketingConsentRecordedAt: record != null
              ? DateTime.tryParse(record['recordedAt']?.toString() ?? '')
              : null,
          marketingConsentSource: record?['source']?.toString(),
          marketingConsentEvidence: record?['evidence']?.toString(),
          marketingConsentTextVersion: record?['consentTextVersion']?.toString(),
          isOptedOut: record != null && record['status'] == 'opted_out'
              ? true
              : customer.isOptedOut,
        );
        notifyListeners();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyCustomers, jsonEncode(_customers.map((c) => c.toJson()).toList()));
      }
    } catch (e) {
      debugPrint('[AppRepository] _reloadConsentForCustomer error: $e');
    }
  }

  /// Bulk records verbal marketing consent for a selected list of customer IDs.
  /// Only updates customers that are explicitly selected.
  /// Sends batched requests using backendClient.bulkRecordConsent.
  /// Reports per-record outcomes accurately — does NOT claim all succeeded when some fail.
  Future<Map<String, dynamic>> bulkRecordMarketingConsent({
    required List<String> customerIds,
    required String source,
    required String evidence,
    String consentTextVersion = 'v2026.1_verbal_confirmed',
    void Function(int processed, int total)? onProgress,
  }) async {
    if (_authToken == null || _authToken!.trim().isEmpty) {
      return {
        'success': false,
        'error': {
          'code': 'UNAUTHORIZED',
          'message': 'You must be logged in to record consent. Please sign in and try again.',
        },
      };
    }

    if (customerIds.isEmpty) {
      return {
        'success': true,
        'totalRequested': 0,
        'succeeded': 0,
        'failed': 0,
        'failures': <Map<String, dynamic>>[],
        'successfulCustomerIds': <String>[],
        'failedCustomerIds': <String>[],
      };
    }

    if (_isBulkRecordingConsent) {
      return {
        'success': false,
        'error': {
          'code': 'OPERATION_IN_PROGRESS',
          'message': 'Bulk consent recording is already in progress. Please wait for it to complete.',
        },
      };
    }

    _isBulkRecordingConsent = true;

    try {
      int succeeded = 0;
      int failed = 0;
      final List<Map<String, dynamic>> failures = [];
      final List<String> successfulCustomerIds = [];
      final List<String> failedCustomerIds = [];

      // Chunk into manageable batches of 100 for bounded payload size and responsive UI progress
      const batchSize = 100;
      final totalToProcess = customerIds.length;
      int processedCount = 0;

      onProgress?.call(0, totalToProcess);

      for (int i = 0; i < customerIds.length; i += batchSize) {
        final chunkIds = customerIds.sublist(
          i,
          (i + batchSize > customerIds.length) ? customerIds.length : i + batchSize,
        );

        final batchPayload = <Map<String, dynamic>>[];
        final Map<String, Customer> batchCustomerMap = {};

        for (final id in chunkIds) {
          final cust = _customers.firstWhere(
            (c) => c.id == id,
            orElse: () => Customer(id: id, name: id, phone: ''),
          );
          batchCustomerMap[id] = cust;
          final cleanDigits = ExcelService.extractClean10Digits(cust.phone);
          final phone = cleanDigits.length == 10 ? '91$cleanDigits' : cleanDigits;

          batchPayload.add({
            'phone': phone,
            'customerId': id,
            'source': source,
            'evidence': evidence,
            'consentTextVersion': consentTextVersion,
          });
        }

        // Call bulk endpoint with bounded timeout
        Map<String, dynamic> response;
        try {
          response = await backendClient.bulkRecordConsent(
            records: batchPayload,
            allowOptOutOverride: false,
          );
        } catch (e) {
          response = {
            'success': false,
            'error': {'code': 'NETWORK_ERROR', 'message': e.toString()},
          };
        }

        // If network error/timeout: check if records were saved before marking as failed or retrying
        if (response['success'] != true && response['results'] == null) {
          // Attempt a safe batchCheckConsent to verify whether database write succeeded before the network dropped
          try {
            final phonesToCheck = batchPayload.map((r) => r['phone'] as String).toList();
            final checkRes = await backendClient.batchCheckConsent(phones: phonesToCheck);
            if (checkRes['success'] == true && checkRes['consents'] is Map) {
              final consentsMap = checkRes['consents'] as Map;
              final syntheticResults = <Map<String, dynamic>>[];
              for (final r in batchPayload) {
                final phone = r['phone'] as String;
                final isOptedIn = consentsMap[phone] == true;
                syntheticResults.add({
                  'phone': phone,
                  'customerId': r['customerId'],
                  'success': isOptedIn,
                  'status': isOptedIn ? 'opted_in' : 'unknown',
                  'error': isOptedIn ? null : (response['error']?['message'] ?? 'Network timeout'),
                });
              }
              response = {
                'success': syntheticResults.every((r) => r['success'] == true),
                'results': syntheticResults,
              };
            }
          } catch (_) {
            // Keep original network failure response
          }
        }

        final now = DateTime.now();

        // Process individual results if returned
        if (response['results'] is List) {
          final resultsList = List<Map<String, dynamic>>.from(response['results']);
          for (final res in resultsList) {
            final cId = res['customerId']?.toString();
            final isSuccess = res['success'] == true;
            final cust = cId != null ? batchCustomerMap[cId] : null;

            if (isSuccess && cId != null) {
              succeeded++;
              successfulCustomerIds.add(cId);

              final idx = _customers.indexWhere((c) => c.id == cId);
              if (idx != -1) {
                _customers[idx] = _customers[idx].copyWith(
                  hasMarketingConsent: true,
                  marketingConsentRecordedAt: res['recordedAt'] != null
                      ? DateTime.tryParse(res['recordedAt'].toString()) ?? now
                      : now,
                  marketingConsentSource: source,
                  marketingConsentEvidence: evidence,
                  marketingConsentTextVersion: consentTextVersion,
                  isOptedOut: false,
                );
              }
            } else {
              failed++;
              final failedId = cId ?? res['phone']?.toString() ?? 'unknown';
              failedCustomerIds.add(failedId);
              failures.add({
                'customerId': failedId,
                'name': cust?.name ?? failedId,
                'phone': res['phone'] ?? cust?.phone ?? '',
                'error': res['error'] ?? 'Consent update rejected',
              });
            }
          }
        } else {
          // If bulk API was completely unavailable (e.g. 404 or network down), report as failed
          for (final id in chunkIds) {
            failed++;
            failedCustomerIds.add(id);
            final cust = batchCustomerMap[id];
            failures.add({
              'customerId': id,
              'name': cust?.name ?? id,
              'phone': cust?.phone ?? '',
              'error': response['error']?['message'] ?? 'Failed to communicate with consent server',
            });
          }
        }

        processedCount += chunkIds.length;
        onProgress?.call(processedCount, totalToProcess);
      }

      // Single notification and single SharedPreferences write at the end!
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCustomers, jsonEncode(_customers.map((c) => c.toJson()).toList()));

      return {
        'success': failed == 0,
        'totalRequested': customerIds.length,
        'succeeded': succeeded,
        'failed': failed,
        'failures': failures,
        'successfulCustomerIds': successfulCustomerIds,
        'failedCustomerIds': failedCustomerIds,
      };
    } finally {
      _isBulkRecordingConsent = false;
    }
  }

  /// Syncs authoritative consent records from backend
  Future<void> syncConsentsFromBackend() async {
    try {
      final records = await backendClient.getConsentList();
      if (records.isEmpty) return;

      bool changed = false;
      for (final rec in records) {
        final phone = rec['phone']?.toString() ?? '';
        final category = rec['consentCategory']?.toString() ?? 'marketing';
        final status = rec['status']?.toString() ?? '';
        final source = rec['source']?.toString();
        final evidence = rec['evidence']?.toString();
        final textVer = rec['consentTextVersion']?.toString();
        final recordedAtStr = rec['recordedAt']?.toString();
        final recordedAt = recordedAtStr != null ? DateTime.tryParse(recordedAtStr) : null;

        final clean10 = phone.replaceAll(RegExp(r'\D'), '');
        final last10 = clean10.length >= 10 ? clean10.substring(clean10.length - 10) : clean10;

        for (int i = 0; i < _customers.length; i++) {
          final cDigits = ExcelService.extractClean10Digits(_customers[i].phone);
          if (cDigits == last10) {
            final isOptedIn = status == 'opted_in';
            if (category == 'utility') {
              _customers[i] = _customers[i].copyWith(
                hasUtilityConsent: isOptedIn,
                utilityConsentRecordedAt: recordedAt,
                utilityConsentSource: source,
                utilityConsentEvidence: evidence,
                utilityConsentTextVersion: textVer,
              );
            } else {
              _customers[i] = _customers[i].copyWith(
                hasMarketingConsent: isOptedIn,
                marketingConsentRecordedAt: recordedAt,
                marketingConsentSource: source,
                marketingConsentEvidence: evidence,
                marketingConsentTextVersion: textVer,
                isOptedOut: status == 'opted_out' ? true : _customers[i].isOptedOut,
              );
            }
            changed = true;
          }
        }
      }

      if (changed) {
        notifyListeners();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyCustomers, jsonEncode(_customers.map((c) => c.toJson()).toList()));
      }
    } catch (e) {
      debugPrint('[AppRepository] syncConsentsFromBackend error: $e');
    }
  }

  Future<int> bulkImportCustomers(List<Customer> imported) async {
    int addedCount = 0;
    final existingPhoneSet = _customers.map((c) => ExcelService.extractClean10Digits(c.phone)).toSet();

    for (final customer in imported) {
      final digits = ExcelService.extractClean10Digits(customer.phone);
      if (!existingPhoneSet.contains(digits)) {
        _customers.insert(0, customer);
        existingPhoneSet.add(digits);
        addedCount++;
      }
    }

    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCustomers, jsonEncode(_customers.map((c) => c.toJson()).toList()));
    return addedCount;
  }

  // --- Campaign Operations ---
  Future<void> addCampaign(Campaign campaign, {List<String>? recipientCustomerIds}) async {
    _campaigns.insert(0, campaign);

    // Deduct WhatsApp credits if campaign is sent
    if (campaign.status == 'Sent') {
      await deductCredits(campaign.recipients);
    }

    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCampaigns, jsonEncode(_campaigns.map((c) => c.toJson()).toList()));
  }

  Future<void> cancelScheduledCampaign(String id) async {
    _campaigns.removeWhere((c) => c.id == id && c.status == 'Scheduled');
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCampaigns, jsonEncode(_campaigns.map((c) => c.toJson()).toList()));
  }

  Future<void> duplicateCampaign(Campaign campaign) async {
    final copy = campaign.copyWith(
      id: 'camp_${DateTime.now().millisecondsSinceEpoch}',
      name: '${campaign.name} (Copy)',
      status: 'Scheduled',
      scheduledDate: DateTime.now().add(const Duration(days: 3)),
    );
    _campaigns.insert(0, copy);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCampaigns, jsonEncode(_campaigns.map((c) => c.toJson()).toList()));
  }

  // --- Customer Groups ---
  Future<void> addGroup(CustomerGroup group) async {
    _groups.add(group);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGroups, jsonEncode(_groups.map((g) => g.toJson()).toList()));
  }

  Future<void> deleteGroup(String id) async {
    _groups.removeWhere((g) => g.id == id && !g.isSystemGroup);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGroups, jsonEncode(_groups.map((g) => g.toJson()).toList()));
  }

  // --- Settings & Credits ---
  Future<void> updateSettings(AppSettings newSettings) async {
    _settings = newSettings;
    // Always carry the active auth token into the new client instance.
    backendClient = GlowBlastBackendClient(
      baseUrl: _settings.backendUrl,
      authToken: _authToken,
    );
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySettings, jsonEncode(_settings.toJson()));
  }

  Future<void> updateCampaignMetrics(
    String campaignId, {
    int? accepted,
    int? sent,
    int? delivered,
    int? read,
    int? failed,
    String? status,
  }) async {
    final idx = _campaigns.indexWhere((c) => c.id == campaignId || c.backendCampaignId == campaignId);
    if (idx != -1) {
      final old = _campaigns[idx];
      _campaigns[idx] = old.copyWith(
        accepted: accepted ?? old.accepted,
        delivered: delivered ?? old.delivered,
        read: read ?? old.read,
        failed: failed ?? old.failed,
        messagesSent: sent ?? old.messagesSent,
        status: status ?? old.status,
      );
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCampaigns, jsonEncode(_campaigns.map((c) => c.toJson()).toList()));
    }
  }

  Future<void> deductCredits(int whatsAppCredits) async {
    final newWa = (_settings.whatsAppCredits - whatsAppCredits).clamp(0, 999999);
    _settings = _settings.copyWith(whatsAppCredits: newWa);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySettings, jsonEncode(_settings.toJson()));
  }

  Future<void> addCredits(int whatsAppCredits) async {
    _settings = _settings.copyWith(
      whatsAppCredits: _settings.whatsAppCredits + whatsAppCredits,
    );
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySettings, jsonEncode(_settings.toJson()));
  }

  // --- Reset Demo Data ---
  Future<void> resetDemoData({bool clearProfile = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCustomers);
    await prefs.remove(_keyCampaigns);
    await prefs.remove(_keyGroups);
    await prefs.remove(_keyTemplates);
    await prefs.remove(_keySettings);
    await prefs.remove(_keyInitializedV3);

    _customers = InitialData.generate200Customers();
    _campaigns = [
      ...InitialData.getPreloadedCampaigns(),
      ...InitialData.getScheduledCampaigns(),
    ];
    _groups = InitialData.getInitialGroups(_customers);
    _templates = InitialData.getInitialTemplates();

    if (clearProfile) {
      _settings = AppSettings();
    } else {
      _settings = _settings.copyWith(whatsAppCredits: 1000);
    }

    await _saveAll(prefs);
    await prefs.setBool(_keyInitializedV3, true);
    notifyListeners();
  }

  // --- WhatsApp Template Operations ---
  Future<void> addTemplate(WhatsAppTemplate template) async {
    _templates.removeWhere((t) => t.id == template.id || t.name.toLowerCase() == template.name.toLowerCase());
    _templates.insert(0, template);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTemplates, jsonEncode(_templates.map((t) => t.toJson()).toList()));
  }

  Future<void> updateTemplateStatus(String id, String status, {String? metaStatus}) async {
    final idx = _templates.indexWhere((t) => t.id == id || t.name.toLowerCase() == id.toLowerCase());
    if (idx != -1) {
      _templates[idx] = _templates[idx].copyWith(
        status: status,
        metaStatus: metaStatus ?? (status == 'approved' ? 'APPROVED' : _templates[idx].metaStatus),
        updatedAt: DateTime.now(),
      );
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyTemplates, jsonEncode(_templates.map((t) => t.toJson()).toList()));
    }
  }

  Future<void> deleteTemplate(String id) async {
    _templates.removeWhere((t) => t.id == id || t.name.toLowerCase() == id.toLowerCase());
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTemplates, jsonEncode(_templates.map((t) => t.toJson()).toList()));
  }

  /// Fetches templates from backend for the specified or active mode without triggering Meta API sync
  Future<List<WhatsAppTemplate>> fetchTemplatesFromBackend({String? mode}) async {
    final effectiveMode = mode ?? (_settings.isWhatsAppProductionMode ? 'production' : 'test');
    try {
      final backendTemplates = await backendClient.getTemplates(mode: effectiveMode);
      if (backendTemplates.isEmpty) return activeTemplates;

      for (final raw in backendTemplates) {
        final tpl = WhatsAppTemplate.fromJson(raw);
        final idx = _templates.indexWhere(
          (t) => (t.id == tpl.id) || (t.name.toLowerCase() == tpl.name.toLowerCase() && t.mode == tpl.mode && t.language == tpl.language),
        );
        if (idx != -1) {
          _templates[idx] = tpl;
        } else {
          _templates.add(tpl);
        }
      }

      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyTemplates, jsonEncode(_templates.map((t) => t.toJson()).toList()));
      return activeTemplates;
    } catch (_) {
      return activeTemplates;
    }
  }

  Future<int> syncTemplatesWithBackend({String? mode}) async {
    final effectiveMode = mode ?? (_settings.isWhatsAppProductionMode ? 'production' : 'test');
    try {
      // 1. Trigger sync from Meta for the active mode
      final syncRes = await backendClient.syncTemplates(mode: effectiveMode);

      // 2. Fetch list for this mode from backend
      final backendTemplates = await backendClient.getTemplates(mode: effectiveMode);
      if (backendTemplates.isEmpty) {
        return (syncRes['syncedCount'] as num?)?.toInt() ?? 0;
      }

      int updatedCount = 0;
      for (final raw in backendTemplates) {
        final tpl = WhatsAppTemplate.fromJson(raw);
        final idx = _templates.indexWhere(
          (t) => (t.id == tpl.id) || (t.name.toLowerCase() == tpl.name.toLowerCase() && t.mode == tpl.mode && t.language == tpl.language),
        );
        if (idx != -1) {
          _templates[idx] = tpl;
        } else {
          _templates.add(tpl);
        }
        updatedCount++;
      }

      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyTemplates, jsonEncode(_templates.map((t) => t.toJson()).toList()));
      return updatedCount;
    } catch (_) {
      return 0;
    }
  }
}
