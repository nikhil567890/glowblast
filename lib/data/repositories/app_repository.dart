import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/customer.dart';
import '../models/campaign.dart';
import '../models/group.dart';
import '../models/settings_model.dart';
import '../demo_data/initial_data.dart';
import '../../services/excel_service.dart';
import '../../services/glowblast_backend_client.dart';

class AppRepository extends ChangeNotifier {
  static const String _keyCustomers = 'glowblast_customers_v3';
  static const String _keyCampaigns = 'glowblast_campaigns_v3';
  static const String _keyGroups = 'glowblast_groups_v3';
  static const String _keySettings = 'glowblast_settings_v3';
  static const String _keyInitializedV3 = 'glowblast_is_initialized_v3';

  List<Customer> _customers = [];
  List<Campaign> _campaigns = [];
  List<CustomerGroup> _groups = [];
  AppSettings _settings = AppSettings();
  bool _isLoading = true;
  late GlowBlastBackendClient backendClient = GlowBlastBackendClient(baseUrl: _settings.backendUrl);

  // Getters
  List<Customer> get customers => List.unmodifiable(_customers);
  List<Campaign> get campaigns => List.unmodifiable(_campaigns);
  List<Campaign> get sentCampaigns => _campaigns.where((c) => c.status == 'Sent' || c.status == 'Accepted').toList();
  List<Campaign> get scheduledCampaigns => _campaigns.where((c) => c.status == 'Scheduled').toList();
  List<Campaign> get realTestCampaigns => _campaigns.where((c) => c.isRealTest).toList();
  List<Campaign> get demoCampaigns => _campaigns.where((c) => !c.isRealTest).toList();
  List<CustomerGroup> get groups => List.unmodifiable(_groups);
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
    _settings = AppSettings();

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

    // Settings
    final setRaw = prefs.getString(_keySettings);
    if (setRaw != null) {
      _settings = AppSettings.fromJson(jsonDecode(setRaw) as Map<String, dynamic>);
    } else {
      _settings = AppSettings();
    }
  }

  void _fallbackToMemory() {
    _customers = InitialData.generate200Customers();
    _campaigns = [
      ...InitialData.getPreloadedCampaigns(),
      ...InitialData.getScheduledCampaigns(),
    ];
    _groups = InitialData.getInitialGroups(_customers);
    _settings = AppSettings();
  }

  Future<void> _saveAll([SharedPreferences? prefs]) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    await p.setString(_keyCustomers, jsonEncode(_customers.map((c) => c.toJson()).toList()));
    await p.setString(_keyCampaigns, jsonEncode(_campaigns.map((c) => c.toJson()).toList()));
    await p.setString(_keyGroups, jsonEncode(_groups.map((g) => g.toJson()).toList()));
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
        delivered: delivered ?? old.delivered,
        read: read ?? old.read,
        failed: failed ?? old.failed,
        messagesSent: (sent ?? accepted) ?? old.messagesSent,
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
    await prefs.remove(_keySettings);
    await prefs.remove(_keyInitializedV3);

    _customers = InitialData.generate200Customers();
    _campaigns = [
      ...InitialData.getPreloadedCampaigns(),
      ...InitialData.getScheduledCampaigns(),
    ];
    _groups = InitialData.getInitialGroups(_customers);

    if (clearProfile) {
      _settings = AppSettings();
    } else {
      _settings = _settings.copyWith(whatsAppCredits: 1000);
    }

    await _saveAll(prefs);
    await prefs.setBool(_keyInitializedV3, true);
    notifyListeners();
  }
}
