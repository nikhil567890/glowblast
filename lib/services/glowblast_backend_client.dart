import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/constants/api_constants.dart';

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

  BackendWhatsAppStatus({
    required this.configured,
    required this.phoneNumberIdConfigured,
    required this.tokenConfigured,
    required this.testMode,
    required this.testRecipientLimit,
    required this.displayNumber,
    required this.apiVersion,
  });

  factory BackendWhatsAppStatus.fromJson(Map<String, dynamic> json) {
    return BackendWhatsAppStatus(
      configured: json['configured'] == true,
      phoneNumberIdConfigured: json['phoneNumberIdConfigured'] == true,
      tokenConfigured: json['tokenConfigured'] == true,
      testMode: json['testMode'] == true,
      testRecipientLimit: (json['testRecipientLimit'] as num?)?.toInt() ?? 5,
      displayNumber: json['displayNumber']?.toString() ?? '+1 (555) 632-5494',
      apiVersion: json['apiVersion']?.toString() ?? 'v22.0',
    );
  }
}

class GlowBlastBackendClient {
  final String baseUrl;
  final http.Client _httpClient;

  GlowBlastBackendClient({
    required String baseUrl,
    http.Client? httpClient,
  })  : baseUrl = ApiConstants.normalizeBackendUrl(baseUrl),
        _httpClient = httpClient ?? http.Client();

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
    required List<Map<String, String>> recipients,
    List<String> optedOutPhones = const [],
    Map<String, dynamic>? metadata,
  }) async {
    final body = jsonEncode({
      'campaignId': campaignId,
      'campaignName': campaignName,
      'businessName': businessName,
      'templateId': templateId,
      'templateName': templateName,
      'templateLanguage': templateLanguage,
      'templateVariables': templateVariables,
      ...?templateComponents == null ? null : {'templateComponents': templateComponents},
      'recipients': recipients,
      'optedOutPhones': optedOutPhones,
      'metadata': metadata,
    });

    try {
      final response = await _httpClient
          .post(
            _uri('/api/campaigns/send'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': response.statusCode == 202 || response.statusCode == 200,
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

  /// Sends a single message directly via POST /api/messages/send
  Future<Map<String, dynamic>> sendSingleMessage({
    required String phone,
    String? name,
    String? templateId,
    required String templateName,
    String templateLanguage = 'en_US',
    List<String>? templateVariables,
    List<Map<String, dynamic>>? templateComponents,
  }) async {
    try {
      final response = await _httpClient
          .post(
            _uri('/api/messages/send'),
            headers: {'Content-Type': 'application/json'},
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
  Future<List<Map<String, dynamic>>> getTemplates() async {
    try {
      final response = await _httpClient
          .get(_uri('/api/templates'))
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
  }) async {
    try {
      final response = await _httpClient
          .post(
            _uri('/api/templates'),
            headers: {'Content-Type': 'application/json'},
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

  /// Synchronizes templates with official Meta WhatsApp Business Platform.
  Future<Map<String, dynamic>> syncTemplates() async {
    try {
      final response = await _httpClient
          .post(
            _uri('/api/templates/sync'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': data['success'] == true,
        'statusCode': response.statusCode,
        ...data,
      };
    } catch (e) {
      return {
        'success': false,
        'error': {
          'code': 'NETWORK_ERROR',
          'message': 'Could not connect to backend template sync: $e',
        },
      };
    }
  }

  /// Updates local approval status of a template.
  Future<Map<String, dynamic>> updateTemplateStatus({
    required String id,
    required String status,
    String? metaStatus,
  }) async {
    try {
      final response = await _httpClient
          .put(
            _uri('/api/templates/$id/status'),
            headers: {'Content-Type': 'application/json'},
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
  Future<Map<String, dynamic>?> getCampaignStatus(String campaignId) async {
    try {
      final response = await _httpClient
          .get(_uri('/api/campaigns/$campaignId/status'))
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
  Future<Map<String, dynamic>?> getCampaignDetails(String campaignId) async {
    try {
      final response = await _httpClient
          .get(_uri('/api/campaigns/$campaignId'))
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
  Stream<Map<String, dynamic>> connectToCampaignEvents(String campaignId) async* {
    final client = http.Client();
    final request = http.Request('GET', _uri('/api/campaigns/$campaignId/events'));
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
}
