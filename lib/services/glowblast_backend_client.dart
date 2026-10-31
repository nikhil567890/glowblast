import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/constants/api_constants.dart';
import '../data/models/business_membership.dart';
import '../data/models/business_member.dart';
import '../data/models/business_invitation.dart';

class BackendHealthStatus {
  final bool isOnline;
  final String? service;
  final String? error;
  final int? statusCode;
  final Duration? latency;
  final String endpointChecked;
  final DateTime checkedAt;

  BackendHealthStatus({
    required this.isOnline,
    this.service,
    this.error,
    this.statusCode,
    this.latency,
    this.endpointChecked = ApiConstants.healthEndpoint,
    DateTime? checkedAt,
  }) : checkedAt = checkedAt ?? DateTime.now();

  String get summary {
    if (isOnline) {
      final ms = latency != null ? ' (${latency!.inMilliseconds}ms)' : '';
      return 'Online · HTTP ${statusCode ?? 200}$ms';
    }
    return error ?? 'Server Unreachable';
  }
}

class BackendWhatsAppStatus {
  final bool configured;
  final bool phoneNumberIdConfigured;
  final bool tokenConfigured;
  final bool testMode;
  final int testRecipientLimit;
  final String displayNumber;
  final String apiVersion;
  final bool isProductionEnabled;
  final bool isProductionConfigured;
  final String? productionDisplayNumber;
  final int productionDailyLimit;

  BackendWhatsAppStatus({
    required this.configured,
    required this.phoneNumberIdConfigured,
    required this.tokenConfigured,
    required this.testMode,
    required this.testRecipientLimit,
    required this.displayNumber,
    required this.apiVersion,
    this.isProductionEnabled = false,
    this.isProductionConfigured = false,
    this.productionDisplayNumber,
    this.productionDailyLimit = 200,
  });

  factory BackendWhatsAppStatus.fromJson(Map<String, dynamic> json) {
    final modes = json['modes'] as Map<String, dynamic>?;
    final prod = modes?['production'] as Map<String, dynamic>?;

    return BackendWhatsAppStatus(
      configured: json['configured'] == true,
      phoneNumberIdConfigured: json['phoneNumberIdConfigured'] == true,
      tokenConfigured: json['tokenConfigured'] == true,
      testMode: json['testMode'] == true,
      testRecipientLimit: (json['testRecipientLimit'] as num?)?.toInt() ?? 5,
      displayNumber: json['displayNumber']?.toString() ?? '+1 (555) 632-5494',
      apiVersion: json['apiVersion']?.toString() ?? 'v22.0',
      isProductionEnabled: prod?['enabled'] == true,
      isProductionConfigured: prod?['configured'] == true,
      productionDisplayNumber: prod?['displayNumber']?.toString(),
      productionDailyLimit: (prod?['dailyUniqueLimit'] as num?)?.toInt() ?? 200,
    );
  }
}

class BusinessWabaConnection {
  final String id;
  final String businessId;
  final String wabaId;
  final String phoneNumberId;
  final String? displayNumber;
  final String mode;
  final bool isActive;
  final String? verifiedName;
  final String? qualityRating;
  final String? source;
  final DateTime? createdAt;

  const BusinessWabaConnection({
    required this.id,
    required this.businessId,
    required this.wabaId,
    required this.phoneNumberId,
    this.displayNumber,
    required this.mode,
    required this.isActive,
    this.verifiedName,
    this.qualityRating,
    this.source,
    this.createdAt,
  });

  factory BusinessWabaConnection.fromJson(Map<String, dynamic> json, {String? source}) {
    return BusinessWabaConnection(
      id: json['id']?.toString() ?? '',
      businessId: json['businessId']?.toString() ?? '',
      wabaId: json['wabaId']?.toString() ?? '',
      phoneNumberId: json['phoneNumberId']?.toString() ?? '',
      displayNumber: json['displayNumber']?.toString(),
      mode: json['mode']?.toString() ?? 'test',
      isActive: json['isActive'] == true || json['connected'] == true,
      verifiedName: json['verifiedName']?.toString(),
      qualityRating: json['qualityRating']?.toString(),
      source: source ?? json['source']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }
}

class GlowBlastBackendClient {
  final String baseUrl;
  final http.Client _httpClient;
  String? authToken;
  String? activeBusinessId;

  GlowBlastBackendClient({
    required String baseUrl,
    http.Client? httpClient,
    this.authToken,
    this.activeBusinessId,
  })  : baseUrl = ApiConstants.normalizeBackendUrl(baseUrl),
        _httpClient = httpClient ?? http.Client();

  Map<String, String> _buildHeaders([String? token, Map<String, String>? extra]) {
    final effectiveToken = token ?? authToken;
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (effectiveToken != null && effectiveToken.trim().isNotEmpty)
        'Authorization': 'Bearer ${effectiveToken.trim()}',
      if (activeBusinessId != null && activeBusinessId!.trim().isNotEmpty)
        'X-Business-Id': activeBusinessId!.trim(),
    };
    if (extra != null) {
      headers.addAll(extra);
    }
    return headers;
  }

  Uri _uri(String path) {
    var cleanBase = baseUrl.trim();
    while (cleanBase.endsWith('/')) {
      cleanBase = cleanBase.substring(0, cleanBase.length - 1);
    }
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$cleanBase$cleanPath');
  }

  /// Checks if backend server is reachable via GET /health.
  /// Uses a 12-second timeout and handles HTTP 2xx, 4xx, 5xx, timeouts, and DNS errors.
  Future<BackendHealthStatus> healthCheck() async {
    final healthUri = _uri(ApiConstants.healthEndpoint);
    final stopwatch = Stopwatch()..start();

    if (kDebugMode) {
      debugPrint('[GlowBlastBackendClient] Checking health at: $healthUri');
    }

    try {
      final response = await _httpClient
          .get(healthUri)
          .timeout(ApiConstants.healthTimeout);
      stopwatch.stop();

      if (kDebugMode) {
        debugPrint('[GlowBlastBackendClient] Health response: HTTP ${response.statusCode} (${stopwatch.elapsedMilliseconds}ms)');
      }

      // HTTP 200 or any 2xx response means Backend is Online
      if (response.statusCode >= 200 && response.statusCode < 300) {
        String serviceName = 'GlowBlast Backend';
        try {
          final data = jsonDecode(response.body);
          if (data is Map && data['service'] != null) {
            serviceName = data['service'].toString();
          }
        } catch (_) {
          // Do not fail if non-JSON, 2xx confirms server is active
        }

        return BackendHealthStatus(
          isOnline: true,
          service: serviceName,
          statusCode: response.statusCode,
          latency: stopwatch.elapsed,
          endpointChecked: healthUri.toString(),
        );
      }

      // If primary /health returned 404, attempt fallback to /api/health
      if (response.statusCode == 404) {
        final fallbackUri = _uri(ApiConstants.fallbackHealthEndpoint);
        try {
          final fallbackRes = await _httpClient.get(fallbackUri).timeout(const Duration(seconds: 6));
          if (fallbackRes.statusCode >= 200 && fallbackRes.statusCode < 300) {
            return BackendHealthStatus(
              isOnline: true,
              service: 'GlowBlast Backend API',
              statusCode: fallbackRes.statusCode,
              latency: stopwatch.elapsed,
              endpointChecked: fallbackUri.toString(),
            );
          }
        } catch (_) {}
      }

      // HTTP 4xx or 5xx server error
      return BackendHealthStatus(
        isOnline: false,
        statusCode: response.statusCode,
        error: 'GlowBlast server returned HTTP ${response.statusCode}.',
        latency: stopwatch.elapsed,
        endpointChecked: healthUri.toString(),
      );
    } on TimeoutException {
      stopwatch.stop();
      if (kDebugMode) {
        debugPrint('[GlowBlastBackendClient] Health check timed out after ${stopwatch.elapsedMilliseconds}ms');
      }
      return BackendHealthStatus(
        isOnline: false,
        error: 'GlowBlast server took too long to respond. Please try again.',
        latency: stopwatch.elapsed,
        endpointChecked: healthUri.toString(),
      );
    } catch (e) {
      stopwatch.stop();
      final errStr = e.toString().toLowerCase();
      String friendlyError = 'GlowBlast server could not be reached. Please check your internet connection.';

      if (errStr.contains('socketexception') || errStr.contains('failed host lookup') || errStr.contains('network is unreachable')) {
        friendlyError = 'GlowBlast server could not be reached. Please check your internet connection.';
      } else if (errStr.contains('certificate') || errStr.contains('handshake')) {
        friendlyError = 'Secure connection error (SSL/TLS).';
      }

      if (kDebugMode) {
        debugPrint('[GlowBlastBackendClient] Health check exception: $e');
      }

      return BackendHealthStatus(
        isOnline: false,
        error: friendlyError,
        latency: stopwatch.elapsed,
        endpointChecked: healthUri.toString(),
      );
    }
  }

  /// Retrieves safe Meta WhatsApp Cloud API configuration status (never exposes secrets).
  Future<BackendWhatsAppStatus?> getWhatsAppStatus() async {
    try {
      final response = await _httpClient
          .get(_uri(ApiConstants.whatsappStatusEndpoint))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return BackendWhatsAppStatus.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Sends a campaign to the backend for real Meta Cloud API dispatch.
  Future<Map<String, dynamic>> sendCampaign({
    required String campaignId,
    required String campaignName,
    String? businessName,
    String? templateId,
    required String templateName,
    String templateLanguage = 'en_US',
    List<String>? templateVariables,
    List<Map<String, dynamic>>? templateComponents,
    required List<Map<String, dynamic>> recipients,
    List<String> optedOutPhones = const [],
    Map<String, dynamic>? metadata,
    String? token,
    String mode = 'test',
  }) async {
    final payload = <String, dynamic>{
      'campaignId': campaignId,
      'campaignName': campaignName,
      'templateName': templateName,
      'templateLanguage': templateLanguage,
      'recipients': recipients,
      'optedOutPhones': optedOutPhones,
      'mode': mode,
    };
    if (businessName != null && businessName.trim().isNotEmpty) {
      payload['businessName'] = businessName.trim();
    }
    if (templateId != null && templateId.trim().isNotEmpty) {
      payload['templateId'] = templateId.trim();
    }
    if (templateVariables != null) {
      payload['templateVariables'] = templateVariables;
    }
    if (templateComponents != null) {
      payload['templateComponents'] = templateComponents;
    }
    if (metadata != null) {
      payload['metadata'] = metadata;
    }
    final headers = _buildHeaders(token);

    try {
      final response = await _httpClient
          .post(
            _uri('/api/campaigns/send'),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}

      final isSuccess = response.statusCode == 202 || response.statusCode == 200;
      return {
        'success': isSuccess,
        'statusCode': response.statusCode,
        ...data,
      };
    } catch (e) {
      return {
        'success': false,
        'statusCode': 0,
        'error': {
          'code': 'NETWORK_ERROR',
          'message': 'Could not connect to GlowBlast backend: $e',
        },
      };
    }
  }

  /// Sends a single message directly via POST /api/messages/send
  Future<Map<String, dynamic>> sendSingleMessage({
    required String phone,
    String? name,
    String? templateId,
    required String templateName,
    String templateLanguage = 'en_US',
    List<String>? templateVariables,
    List<Map<String, dynamic>>? templateComponents,
    String? token,
  }) async {
    try {
      final response = await _httpClient
          .post(
            _uri('/api/messages/send'),
            headers: _buildHeaders(token),
            body: jsonEncode({
              'phone': phone,
              'name': name,
              'templateId': templateId,
              'templateName': templateName,
              'templateLanguage': templateLanguage,
              'templateVariables': templateVariables,
              ...?templateComponents == null ? null : {'templateComponents': templateComponents},
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': response.statusCode == 200,
        'statusCode': response.statusCode,
        ...data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': {
          'code': 'NETWORK_ERROR',
          'message': 'Failed to connect to backend: $e',
        },
      };
    }
  }

  /// Fetches all registered WhatsApp templates from backend.
  Future<List<Map<String, dynamic>>> getTemplates({String? mode, String? token}) async {
    try {
      final query = mode != null ? '?mode=$mode' : '';
      final response = await _httpClient
          .get(_uri('/api/templates$query'), headers: _buildHeaders(token))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['templates'] is List) {
          return List<Map<String, dynamic>>.from(data['templates']);
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Synchronizes templates with Meta WhatsApp Business Account (?mode=test|production).
  Future<Map<String, dynamic>> syncTemplates({String mode = 'test', String? token}) async {
    try {
      final response = await _httpClient
          .post(
            _uri('/api/templates/sync?mode=$mode'),
            headers: _buildHeaders(token),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'statusCode': response.statusCode,
        ...data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': {
          'code': 'NETWORK_ERROR',
          'message': 'Failed to sync templates: $e',
        },
      };
    }
  }

  /// Submits a new template to the backend and optionally Meta WhatsApp Cloud API.
  Future<Map<String, dynamic>> createTemplate({
    required String name,
    required String displayName,
    String? description,
    String category = 'MARKETING',
    String language = 'en_US',
    required String body,
    List<String>? variables,
    Map<String, String>? exampleValues,
    bool submitToMeta = false,
    String? token,
  }) async {
    try {
      final response = await _httpClient
          .post(
            _uri('/api/templates'),
            headers: _buildHeaders(token),
            body: jsonEncode({
              'name': name,
              'displayName': displayName,
              'description': description,
              'category': category,
              'language': language,
              'body': body,
              'variables': variables,
              'exampleValues': exampleValues,
              'submitToMeta': submitToMeta,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': response.statusCode == 201 || response.statusCode == 200,
        'statusCode': response.statusCode,
        ...data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': {
          'code': 'NETWORK_ERROR',
          'message': 'Could not connect to GlowBlast backend: $e',
        },
      };
    }
  }

  /// Updates local approval status of a template.
  Future<Map<String, dynamic>> updateTemplateStatus({
    required String id,
    required String status,
    String? metaStatus,
    String? token,
  }) async {
    try {
      final response = await _httpClient
          .put(
            _uri('/api/templates/$id/status'),
            headers: _buildHeaders(token),
            body: jsonEncode({
              'status': status,
              'metaStatus': metaStatus,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': response.statusCode == 200,
        'statusCode': response.statusCode,
        ...data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': {
          'code': 'NETWORK_ERROR',
          'message': 'Could not update template status: $e',
        },
      };
    }
  }

  /// Gets the current authoritative campaign status counters.
  Future<Map<String, dynamic>?> getCampaignStatus(String campaignId, {String? token}) async {
    try {
      final response = await _httpClient
          .get(_uri('/api/campaigns/$campaignId/status'), headers: _buildHeaders(token))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        // Ensure callers expecting decoded['campaign'] or top-level fields both work seamlessly
        if (decoded['campaign'] == null) {
          decoded['campaign'] = Map<String, dynamic>.from(decoded);
        }
        return decoded;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Gets full campaign details including per-recipient message results and errors.
  Future<Map<String, dynamic>?> getCampaignDetails(String campaignId, {String? token}) async {
    try {
      final response = await _httpClient
          .get(_uri('/api/campaigns/$campaignId'), headers: _buildHeaders(token))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Connects to the SSE event stream for live campaign progress and status events.
  Stream<Map<String, dynamic>> connectToCampaignEvents(String campaignId, {String? token}) async* {
    final client = http.Client();
    final effectiveToken = token ?? authToken;
    final query = effectiveToken != null && effectiveToken.isNotEmpty ? '?token=$effectiveToken' : '';
    final request = http.Request('GET', _uri('/api/campaigns/$campaignId/events$query'));
    final headers = _buildHeaders(token);
    headers.forEach((key, value) {
      request.headers[key] = value;
    });
    request.headers['Accept'] = 'text/event-stream';
    request.headers['Cache-Control'] = 'no-cache';

    try {
      final streamedResponse = await client.send(request);
      final stream = streamedResponse.stream.transform(utf8.decoder).transform(const LineSplitter());

      String currentEvent = '';
      await for (final line in stream) {
        if (line.startsWith('event: ')) {
          currentEvent = line.substring(7).trim();
        } else if (line.startsWith('data: ')) {
          final dataStr = line.substring(6).trim();
          try {
            final data = jsonDecode(dataStr) as Map<String, dynamic>;
            data['eventType'] = currentEvent;
            yield data;
          } catch (_) {}
        }
      }
    } catch (_) {
      // Disconnected
    } finally {
      client.close();
    }
  }

  // ==========================================
  // Authentication & Brevo OTP Endpoints
  // ==========================================

  /// Requests a 6-digit registration OTP sent to user email via backend Brevo service.
  Future<Map<String, dynamic>> requestRegisterOtp({
    required String name,
    required String email,
    required String password,
    String? businessName,
    String? phone,
  }) async {
    try {
      final endpointUri = _uri('/api/auth/register/request-otp');
      final payload = <String, dynamic>{
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        'password': password,
      };
      if (businessName != null && businessName.trim().isNotEmpty) {
        payload['businessName'] = businessName.trim();
      }
      if (phone != null && phone.trim().isNotEmpty) {
        payload['phone'] = phone.trim();
      }

      final response = await _httpClient
          .post(
            endpointUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}

      final isSuccess = response.statusCode >= 200 && response.statusCode < 300;
      if (!isSuccess) {
        final errorMap = data['error'] as Map<String, dynamic>?;
        String message = errorMap?['message'] as String? ?? '';
        if (response.statusCode == 404) {
          message = 'Authentication service is deploying on the cloud server. Please try again shortly.';
        } else if (message.isEmpty) {
          message = 'Registration request failed (HTTP ${response.statusCode}).';
        }
        return {
          'success': false,
          'statusCode': response.statusCode,
          'error': {
            'code': errorMap?['code'] ?? 'SERVER_ERROR',
            'message': message,
          },
        };
      }

      return {
        'success': true,
        'statusCode': response.statusCode,
        ...data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': {
          'code': 'NETWORK_ERROR',
          'message': 'Unable to connect to GlowBlast backend. Please check network connection.',
        },
      };
    }
  }

  /// Verifies the 6-digit OTP and activates the account, receiving the authenticated session token.
  Future<Map<String, dynamic>> verifyRegisterOtp({
    required String email,
    required String otp,
  }) async {
    try {
      final endpointUri = _uri('/api/auth/register/verify-otp');
      final response = await _httpClient
          .post(
            endpointUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email.trim().toLowerCase(),
              'otp': otp.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}

      final isSuccess = response.statusCode >= 200 && response.statusCode < 300;
      if (!isSuccess) {
        final errorMap = data['error'] as Map<String, dynamic>?;
        String message = errorMap?['message'] as String? ?? '';
        if (response.statusCode == 404) {
          message = 'Authentication service is deploying on the cloud server. Please try again shortly.';
        } else if (message.isEmpty) {
          message = 'Verification request failed (HTTP ${response.statusCode}).';
        }
        return {
          'success': false,
          'statusCode': response.statusCode,
          'error': {
            'code': errorMap?['code'] ?? 'SERVER_ERROR',
            'message': message,
          },
        };
      }

      return {
        'success': true,
        'statusCode': response.statusCode,
        ...data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': {
          'code': 'NETWORK_ERROR',
          'message': 'Unable to connect to GlowBlast backend. Please check network connection.',
        },
      };
    }
  }

  /// Authenticates an existing user via email and password.
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final endpointUri = _uri('/api/auth/login');
      final response = await _httpClient
          .post(
            endpointUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email.trim().toLowerCase(),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15));

      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}

      final isSuccess = response.statusCode >= 200 && response.statusCode < 300;
      if (!isSuccess) {
        final errorMap = data['error'] as Map<String, dynamic>?;
        String message = errorMap?['message'] as String? ?? '';
        if (response.statusCode == 404) {
          message = 'Authentication service is deploying on the cloud server. Please try again shortly.';
        } else if (message.isEmpty) {
          message = 'Login request failed (HTTP ${response.statusCode}).';
        }
        return {
          'success': false,
          'statusCode': response.statusCode,
          'error': {
            'code': errorMap?['code'] ?? 'SERVER_ERROR',
            'message': message,
          },
        };
      }

      return {
        'success': true,
        'statusCode': response.statusCode,
        ...data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': {
          'code': 'NETWORK_ERROR',
          'message': 'Unable to connect to GlowBlast backend. Please check network connection.',
        },
      };
    }
  }

  /// Logs out of backend session.
  Future<void> logout({String? token}) async {
    try {
      await _httpClient
          .post(
            _uri('/api/auth/logout'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  /// Records auditable customer WhatsApp consent with category (marketing or utility)
  Future<Map<String, dynamic>> recordConsent({
    required String phone,
    String? customerId,
    String consentCategory = 'marketing',
    required String status,
    required String source,
    required String evidence,
    String? consentTextVersion,
    bool? allowOptOutOverride,
    String? token,
  }) async {
    final headers = _buildHeaders(token);

    try {
      final response = await _httpClient
          .post(
            _uri('/api/consent/record'),
            headers: headers,
            body: jsonEncode({
              'phone': phone,
              'consentCategory': consentCategory,
              'status': status,
              'source': source,
              'evidence': evidence,
              ...?customerId == null ? null : {'customerId': customerId},
              ...?consentTextVersion == null ? null : {'consentTextVersion': consentTextVersion},
              ...?allowOptOutOverride == null ? null : {'allowOptOutOverride': allowOptOutOverride},
            }),
          )
          .timeout(const Duration(seconds: 12));

      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}

      return {
        'success': response.statusCode >= 200 && response.statusCode < 300 && data['success'] == true,
        'statusCode': response.statusCode,
        ...data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': {
          'code': 'NETWORK_ERROR',
          'message': 'Failed to record consent: $e',
        },
      };
    }
  }

  /// Retrieves consent status for a specific phone number and category
  Future<Map<String, dynamic>> getConsent({
    required String phone,
    String? category,
    String? token,
  }) async {
    final headers = _buildHeaders(token);

    try {
      final query = category != null ? '?category=$category' : '';
      final response = await _httpClient
          .get(_uri('/api/consent/$phone$query'), headers: headers)
          .timeout(const Duration(seconds: 10));

      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}

      return {
        'success': response.statusCode >= 200 && response.statusCode < 300,
        'statusCode': response.statusCode,
        ...data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': {
          'code': 'NETWORK_ERROR',
          'message': 'Failed to retrieve consent: $e',
        },
      };
    }
  }

  /// Batch checks consent status for a list of phone numbers
  Future<Map<String, dynamic>> batchCheckConsent({
    required List<String> phones,
    String category = 'marketing',
    String? token,
  }) async {
    final headers = _buildHeaders(token);

    try {
      final response = await _httpClient
          .post(
            _uri('/api/consent/batch-check'),
            headers: headers,
            body: jsonEncode({
              'phones': phones,
              'category': category,
            }),
          )
          .timeout(const Duration(seconds: 12));

      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}

      return {
        'success': response.statusCode >= 200 && response.statusCode < 300 && data['success'] == true,
        'statusCode': response.statusCode,
        ...data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': {
          'code': 'NETWORK_ERROR',
          'message': 'Failed to batch check consent: $e',
        },
      };
    }
  }

  /// Lists all consent records from authoritative registry
  Future<List<Map<String, dynamic>>> getConsentList({
    String? category,
    String? token,
  }) async {
    final headers = _buildHeaders(token);

    try {
      final query = category != null ? '?category=$category' : '';
      final response = await _httpClient
          .get(_uri('/api/consent$query'), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        if (data is Map && data['records'] is List) {
          return List<Map<String, dynamic>>.from(data['records']);
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Bulk records verbal marketing opt-in consent for multiple customers.
  /// Calls POST /api/consent/bulk-record. Each entry is processed independently
  /// and partial failures are reported accurately.
  Future<Map<String, dynamic>> bulkRecordConsent({
    required List<Map<String, dynamic>> records,
    bool allowOptOutOverride = false,
    String? token,
  }) async {
    final headers = _buildHeaders(token);

    try {
      final response = await _httpClient
          .post(
            _uri('/api/consent/bulk-record'),
            headers: headers,
            body: jsonEncode({
              'records': records,
              'allowOptOutOverride': allowOptOutOverride,
            }),
          )
          .timeout(const Duration(seconds: 60));

      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}

      return {
        'success': response.statusCode >= 200 && response.statusCode < 300 && data['success'] == true,
        'statusCode': response.statusCode,
        ...data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': {
          'code': 'NETWORK_ERROR',
          'message': 'Failed to bulk record consent: $e',
        },
      };
    }
  }

  /// Safely deletes multiple customer records from backend while strictly preserving
  /// consent status, opt-out records, compliance audit trail, and campaign history.
  Future<Map<String, dynamic>> bulkDeleteCustomers({
    required List<String> customerIds,
    String? token,
  }) async {
    final headers = _buildHeaders(token);

    try {
      http.Response response = await _httpClient
          .delete(
            _uri('/api/customers'),
            headers: headers,
            body: jsonEncode({'customerIds': customerIds}),
          )
          .timeout(const Duration(seconds: 15));

      // Resilient fallback: If HTTP DELETE route is rejected (e.g. 404/405 or stripped body by middleboxes), retry with POST
      if (response.statusCode == 404 || response.statusCode == 405) {
        try {
          final fallbackResponse = await _httpClient
              .post(
                _uri('/api/customers/bulk-delete'),
                headers: headers,
                body: jsonEncode({'customerIds': customerIds}),
              )
              .timeout(const Duration(seconds: 15));
          if (fallbackResponse.statusCode < 400 || fallbackResponse.statusCode != 404) {
            response = fallbackResponse;
          }
        } catch (_) {}
      }

      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}

      final isSuccess = response.statusCode >= 200 && response.statusCode < 300 && data['success'] == true;
      return {
        'success': isSuccess,
        'statusCode': response.statusCode,
        'deletedCount': data['deletedCount'] ?? 0,
        'deletedCustomerIds': (data['deletedCustomerIds'] as List?)?.cast<String>() ?? <String>[],
        ...data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': {
          'code': 'NETWORK_ERROR',
          'message': 'Failed to delete customers: $e',
        },
      };
    }
  }

  // ==========================================
  // Multi-Business SaaS Endpoints
  // ==========================================

  /// Retrieves the list of businesses where the authenticated user is an active member.
  Future<List<BusinessMembership>> getMyBusinesses({String? token}) async {
    try {
      final headers = _buildHeaders(token);
      final response = await _httpClient
          .get(_uri('/api/businesses'), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['businesses'] is List) {
          final list = data['businesses'] as List;
          return list
              .map((b) => BusinessMembership.fromJson(Map<String, dynamic>.from(b)))
              .toList();
        }
      }
      return [];
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GlowBlastBackendClient] Failed to fetch businesses: $e');
      }
      return [];
    }
  }

  /// Creates a new business and atomically assigns the user as its Owner.
  Future<Map<String, dynamic>> createBusiness({
    required String name,
    required String slug,
    String? phone,
    String? email,
    String timezone = 'UTC',
    String? token,
  }) async {
    try {
      final headers = _buildHeaders(token);
      final response = await _httpClient
          .post(
            _uri('/api/businesses'),
            headers: headers,
            body: jsonEncode({
              'name': name.trim(),
              'slug': slug.trim().toLowerCase(),
              if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
              if (email != null && email.trim().isNotEmpty) 'email': email.trim().toLowerCase(),
              'timezone': timezone.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}

      final isSuccess = response.statusCode == 201 || response.statusCode == 200;
      return {
        'success': isSuccess,
        'statusCode': response.statusCode,
        ...data,
      };
    } catch (e) {
      return {
        'success': false,
        'statusCode': 0,
        'error': {
          'code': 'NETWORK_ERROR',
          'message': 'Failed to create business: $e',
        },
      };
    }
  }

  /// Gets details of a specific business (verifying membership).
  Future<Map<String, dynamic>?> getBusinessDetails(String businessId, {String? token}) async {
    try {
      final headers = _buildHeaders(token, {'X-Business-Id': businessId});
      final response = await _httpClient
          .get(_uri('/api/businesses/$businessId'), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }


  /// Retrieves WhatsApp connection for the active business.
  Future<BusinessWabaConnection?> getBusinessWabaConnection({
    String mode = 'test',
    String? businessId,
    String? token,
  }) async {
    final effectiveBiz = businessId ?? activeBusinessId;
    if (effectiveBiz == null) return null;
    final headers = _buildHeaders(token, {'X-Business-Id': effectiveBiz});

    try {
      final response = await _httpClient
          .get(_uri('/api/whatsapp/connection?mode=$mode'), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['connected'] == true && data['connection'] is Map) {
          return BusinessWabaConnection.fromJson(
            Map<String, dynamic>.from(data['connection']),
            source: data['source']?.toString(),
          );
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Connects or updates a WhatsApp Business Account connection for the active business.
  Future<Map<String, dynamic>> connectBusinessWaba({
    required String wabaId,
    required String phoneNumberId,
    required String accessToken,
    String? displayNumber,
    String mode = 'test',
    String? verifiedName,
    String? businessId,
    String? token,
  }) async {
    final effectiveBiz = businessId ?? activeBusinessId;
    final headers = _buildHeaders(token, effectiveBiz != null ? {'X-Business-Id': effectiveBiz} : null);

    try {
      final response = await _httpClient
          .post(
            _uri('/api/whatsapp/connection'),
            headers: headers,
            body: jsonEncode({
              'wabaId': wabaId.trim(),
              'phoneNumberId': phoneNumberId.trim(),
              'accessToken': accessToken.trim(),
              'displayNumber': displayNumber?.trim(),
              'mode': mode,
              'verifiedName': verifiedName?.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200 || response.statusCode == 201,
        'statusCode': response.statusCode,
        if (data is Map<String, dynamic>) ...data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': {'message': e.toString()},
      };
    }
  }

  /// Disconnects WhatsApp connection for the active business.
  Future<bool> disconnectBusinessWaba({
    String mode = 'test',
    String? businessId,
    String? token,
  }) async {
    final effectiveBiz = businessId ?? activeBusinessId;
    final headers = _buildHeaders(token, effectiveBiz != null ? {'X-Business-Id': effectiveBiz} : null);

    try {
      final response = await _httpClient
          .delete(_uri('/api/whatsapp/connection?mode=$mode'), headers: headers)
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // --------------------------------------------------------------------------
  // Phase 4: Team Management & Business Profile API Methods
  // --------------------------------------------------------------------------

  /// Lists all team members of the given or active business.
  Future<List<BusinessMember>> getBusinessMembers({
    String? businessId,
    String? token,
  }) async {
    final effectiveBiz = businessId ?? activeBusinessId;
    if (effectiveBiz == null) return [];
    final headers = _buildHeaders(token, {'X-Business-Id': effectiveBiz});

    try {
      final response = await _httpClient
          .get(_uri('/api/businesses/$effectiveBiz/members'), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['members'] is List) {
          return (data['members'] as List)
              .map((m) => BusinessMember.fromJson(Map<String, dynamic>.from(m)))
              .toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Invites a new team member by email.
  Future<Map<String, dynamic>> inviteBusinessMember({
    required String email,
    required String role,
    String? businessId,
    String? token,
  }) async {
    final effectiveBiz = businessId ?? activeBusinessId;
    if (effectiveBiz == null) {
      return {'success': false, 'error': {'code': 'NO_ACTIVE_BUSINESS', 'message': 'No active business selected'}};
    }
    final headers = _buildHeaders(token, {'X-Business-Id': effectiveBiz});

    try {
      final response = await _httpClient
          .post(
            _uri('/api/businesses/$effectiveBiz/invitations'),
            headers: headers,
            body: jsonEncode({
              'email': email.trim().toLowerCase(),
              'role': role.trim().toLowerCase(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 201 || response.statusCode == 200,
        'statusCode': response.statusCode,
        if (data is Map<String, dynamic>) ...data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': {'code': 'NETWORK_ERROR', 'message': e.toString()},
      };
    }
  }

  /// Lists pending invitations for the business.
  Future<List<BusinessInvitation>> getBusinessInvitations({
    String? businessId,
    String? token,
  }) async {
    final effectiveBiz = businessId ?? activeBusinessId;
    if (effectiveBiz == null) return [];
    final headers = _buildHeaders(token, {'X-Business-Id': effectiveBiz});

    try {
      final response = await _httpClient
          .get(_uri('/api/businesses/$effectiveBiz/invitations'), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['invitations'] is List) {
          return (data['invitations'] as List)
              .map((inv) => BusinessInvitation.fromJson(Map<String, dynamic>.from(inv)))
              .toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Revokes a pending invitation.
  Future<bool> revokeBusinessInvitation({
    required String invitationId,
    String? businessId,
    String? token,
  }) async {
    final effectiveBiz = businessId ?? activeBusinessId;
    if (effectiveBiz == null) return false;
    final headers = _buildHeaders(token, {'X-Business-Id': effectiveBiz});

    try {
      final response = await _httpClient
          .delete(_uri('/api/businesses/$effectiveBiz/invitations/$invitationId'), headers: headers)
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Changes a member's role (admin or staff).
  Future<Map<String, dynamic>> updateMemberRole({
    required String userId,
    required String role,
    String? businessId,
    String? token,
  }) async {
    final effectiveBiz = businessId ?? activeBusinessId;
    if (effectiveBiz == null) {
      return {'success': false, 'error': {'code': 'NO_ACTIVE_BUSINESS', 'message': 'No active business selected'}};
    }
    final headers = _buildHeaders(token, {'X-Business-Id': effectiveBiz});

    try {
      final response = await _httpClient
          .patch(
            _uri('/api/businesses/$effectiveBiz/members/$userId'),
            headers: headers,
            body: jsonEncode({'role': role}),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200,
        'statusCode': response.statusCode,
        if (data is Map<String, dynamic>) ...data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': {'code': 'NETWORK_ERROR', 'message': e.toString()},
      };
    }
  }

  /// Removes a member from the business.
  Future<Map<String, dynamic>> removeBusinessMember({
    required String userId,
    String? businessId,
    String? token,
  }) async {
    final effectiveBiz = businessId ?? activeBusinessId;
    if (effectiveBiz == null) {
      return {'success': false, 'error': {'code': 'NO_ACTIVE_BUSINESS', 'message': 'No active business selected'}};
    }
    final headers = _buildHeaders(token, {'X-Business-Id': effectiveBiz});

    try {
      final response = await _httpClient
          .delete(_uri('/api/businesses/$effectiveBiz/members/$userId'), headers: headers)
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200,
        'statusCode': response.statusCode,
        if (data is Map<String, dynamic>) ...data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': {'code': 'NETWORK_ERROR', 'message': e.toString()},
      };
    }
  }

  /// Accepts an invitation using a secure token.
  Future<Map<String, dynamic>> acceptBusinessInvitation({
    required String invitationToken,
    String? token,
  }) async {
    final headers = _buildHeaders(token);

    try {
      final response = await _httpClient
          .post(
            _uri('/api/businesses/invitations/accept'),
            headers: headers,
            body: jsonEncode({'token': invitationToken.trim()}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200,
        'statusCode': response.statusCode,
        if (data is Map<String, dynamic>) ...data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': {'code': 'NETWORK_ERROR', 'message': e.toString()},
      };
    }
  }

  /// Updates business profile details (displayName, phone, email, timezone, logoUrl).
  Future<Map<String, dynamic>> updateBusinessProfile({
    required String businessId,
    String? displayName,
    String? phone,
    String? email,
    String? timezone,
    String? logoUrl,
    String? token,
  }) async {
    final headers = _buildHeaders(token, {'X-Business-Id': businessId});

    try {
      final response = await _httpClient
          .put(
            _uri('/api/businesses/$businessId'),
            headers: headers,
            body: jsonEncode({
              if (displayName != null) 'displayName': displayName.trim(),
              if (phone != null) 'phone': phone.trim(),
              if (email != null) 'email': email.trim(),
              if (timezone != null) 'timezone': timezone.trim(),
              if (logoUrl != null) 'logoUrl': logoUrl.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200,
        'statusCode': response.statusCode,
        if (data is Map<String, dynamic>) ...data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': {'code': 'NETWORK_ERROR', 'message': e.toString()},
      };
    }
  }
}

