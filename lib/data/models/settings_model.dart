import '../../core/constants/api_constants.dart';

class AppSettings {
  final String fullName;
  final String businessName;
  final String phone;
  final bool isWhatsAppConnected;
  final int whatsAppCredits;
  final String themeMode; // 'system', 'light', 'dark'
  final String messagingMode; // 'demo' or 'testMode'
  final String backendUrl; // URL of the GlowBlast backend

  AppSettings({
    this.fullName = '',
    this.businessName = '',
    this.phone = '',
    this.isWhatsAppConnected = true,
    this.whatsAppCredits = 1000,
    this.themeMode = 'system',
    this.messagingMode = 'demo',
    this.backendUrl = ApiConstants.defaultProductionBackendUrl,
  });

  bool get hasProfile =>
      fullName.trim().isNotEmpty &&
      businessName.trim().isNotEmpty &&
      phone.trim().isNotEmpty;

  bool get isWhatsAppTestMode => messagingMode == 'testMode';

  // Convenient alias for personalization
  String get spaName => businessName;

  Map<String, dynamic> toJson() => {
    'fullName': fullName,
    'businessName': businessName,
    'phone': phone,
    'isWhatsAppConnected': isWhatsAppConnected,
    'whatsAppCredits': whatsAppCredits,
    'themeMode': themeMode,
    'messagingMode': messagingMode,
    'backendUrl': backendUrl,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final business = json['businessName'] as String? ?? json['spaName'] as String? ?? '';
    final name = json['fullName'] as String? ?? json['userName'] as String? ?? '';
    final phone = json['phone'] as String? ?? json['userPhone'] as String? ?? '';

    // If it was the legacy default hard-coded demo profile, treat as empty so Landing page triggers
    final isLegacyDemo = (name == 'Priya') || (business == 'Serenity Spa & Wellness');

    // Automatic migration of stale local development / emulator URLs to the production cloud URL
    final rawBackendUrl = json['backendUrl'] as String?;
    final migratedBackendUrl = ApiConstants.normalizeBackendUrl(rawBackendUrl);

    return AppSettings(
      fullName: isLegacyDemo ? '' : name,
      businessName: isLegacyDemo ? '' : business,
      phone: isLegacyDemo ? '' : phone,
      isWhatsAppConnected: json['isWhatsAppConnected'] as bool? ?? true,
      whatsAppCredits: (json['whatsAppCredits'] as num?)?.toInt() ?? 1000,
      themeMode: json['themeMode'] as String? ?? 'system',
      messagingMode: json['messagingMode'] as String? ?? 'demo',
      backendUrl: migratedBackendUrl,
    );
  }

  AppSettings copyWith({
    String? fullName,
    String? businessName,
    String? phone,
    bool? isWhatsAppConnected,
    int? whatsAppCredits,
    String? themeMode,
    String? messagingMode,
    String? backendUrl,
  }) {
    return AppSettings(
      fullName: fullName ?? this.fullName,
      businessName: businessName ?? this.businessName,
      phone: phone ?? this.phone,
      isWhatsAppConnected: isWhatsAppConnected ?? this.isWhatsAppConnected,
      whatsAppCredits: whatsAppCredits ?? this.whatsAppCredits,
      themeMode: themeMode ?? this.themeMode,
      messagingMode: messagingMode ?? this.messagingMode,
      backendUrl: backendUrl != null
          ? ApiConstants.normalizeBackendUrl(backendUrl)
          : this.backendUrl,
    );
  }
}
