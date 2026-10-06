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
  late GlowBlastBackendClient backendClient = GlowBlastBackendClient(baseUrl: _settings.backendUrl);

  // Auth getters
  bool get isAuthenticated => _authToken != null && _currentUser != null;
  bool get hasProfile => _settings.hasProfile;
  AuthUser? get currentUser => _currentUser;
  String? get authToken => _authToken;

  // Getters
  List<Customer> get customers => List.unmodifiable(_customers);
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
  List<WhatsAppTemplate> get pendingTemplates => _templates.where((t) => t.isPending).toList();
  List<WhatsAppTemplate> get draftTemplates => _templates.where((t) => t.isDraft).toList();

  WhatsAppTemplate? getTemplateById(String id) {
    try {
      return _templates.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  WhatsAppTemplate? getTemplateByName(String name) {
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

    // Always re-sync backendClient with active settings
    backendClient = GlowBlastBackendClient(baseUrl: _settings.backendUrl);

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
  }

  /// Securely saves authenticated session and user profile.
  Future<void> saveAuthSession(String token, AuthUser user) async {
    _authToken = token;
    _currentUser = user;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAuthToken, token);
    await prefs.setString(_keyAuthUser, jsonEncode(user.toJson()));
  }

  /// Clears active authenticated session on logout without wiping business data.
  Future<void> clearAuthSession() async {
    _authToken = null;
    _currentUser = null;
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
    backendClient = GlowBlastBackendClient(baseUrl: _settings.backendUrl);
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
    backendClient = GlowBlastBackendClient(baseUrl: _settings.backendUrl);
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

  Future<int> syncTemplatesWithBackend() async {
    try {
      final backendTemplates = await backendClient.getTemplates();
      if (backendTemplates.isEmpty) return 0;

      int updatedCount = 0;
      for (final raw in backendTemplates) {
        final tpl = WhatsAppTemplate.fromJson(raw);
        final idx = _templates.indexWhere((t) => t.name.toLowerCase() == tpl.name.toLowerCase());
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
