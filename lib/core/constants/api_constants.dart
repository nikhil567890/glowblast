import 'package:flutter/foundation.dart';

/// Centralized API and backend configuration constants for GlowBlast.
class ApiConstants {
  /// Production cloud backend hosted on Render (public HTTPS).
  static const String defaultProductionBackendUrl = 'https://glowblast-api.onrender.com';

  /// Primary health endpoint verified from physical Android devices.
  static const String healthEndpoint = '/health';

  /// Secondary fallback health endpoint.
  static const String fallbackHealthEndpoint = '/api/health';

  /// Campaign dispatch endpoint.
  static const String campaignSendEndpoint = '/api/campaigns/send';

  /// Single message dispatch endpoint.
  static const String singleMessageSendEndpoint = '/api/messages/send';

  /// WhatsApp safe configuration status endpoint.
  static const String whatsappStatusEndpoint = '/api/whatsapp/status';

  /// Standard network timeouts.
  static const Duration healthTimeout = Duration(seconds: 12);
  static const Duration requestTimeout = Duration(seconds: 15);

  /// Checks if a given URL is a local or development emulator address that must be migrated.
  static bool isLocalOrDevUrl(String? url) {
    if (url == null || url.trim().isEmpty) return true;
    final clean = url.trim().toLowerCase();
    return clean.contains('10.0.2.2') ||
        clean.contains('localhost') ||
        clean.contains('127.0.0.1') ||
        clean.startsWith('http://192.168.') ||
        clean.startsWith('http://10.') ||
        clean.startsWith('http://172.') ||
        clean == 'http://localhost:3000' ||
        clean == 'http://10.0.2.2:3000';
  }

  /// Normalizes and migrates a backend URL to the production cloud URL.
  static String normalizeBackendUrl(String? url) {
    if (url == null || url.trim().isEmpty || isLocalOrDevUrl(url)) {
      return defaultProductionBackendUrl;
    }

    var clean = url.trim();
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }

    // In release mode, only allow secure HTTPS URLs
    if (kReleaseMode && !clean.startsWith('https://')) {
      return defaultProductionBackendUrl;
    }

    return clean;
  }
}
