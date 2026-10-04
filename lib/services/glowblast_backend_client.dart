import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class BackendHealthStatus {
  final bool isOnline;
  final String? service;
  final String? error;

  BackendHealthStatus({required this.isOnline, this.service, this.error});
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
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  Uri _uri(String path) {
    final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$cleanBase$path');
  }

  /// Checks if backend server is reachable.
  Future<BackendHealthStatus> healthCheck() async {
    try {
      final response = await _httpClient.get(_uri('/api/health')).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return BackendHealthStatus(isOnline: true, service: data['service']?.toString());
      }
      return BackendHealthStatus(isOnline: false, error: 'HTTP ${response.statusCode}');
    } catch (e) {
      return BackendHealthStatus(isOnline: false, error: e.toString());
    }
  }

  /// Retrieves safe Meta WhatsApp Cloud API configuration status (never exposes secrets).
  Future<BackendWhatsAppStatus?> getWhatsAppStatus() async {
    try {
      final response = await _httpClient.get(_uri('/api/whatsapp/status')).timeout(const Duration(seconds: 4));
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
    String templateName = 'hello_world',
    String templateLanguage = 'en_US',
    required List<Map<String, String>> recipients,
    List<String> optedOutPhones = const [],
  }) async {
    final body = jsonEncode({
      'campaignId': campaignId,
      'campaignName': campaignName,
      'businessName': businessName,
      'templateName': templateName,
      'templateLanguage': templateLanguage,
      'recipients': recipients,
      'optedOutPhones': optedOutPhones,
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
    String templateName = 'hello_world',
    String templateLanguage = 'en_US',
  }) async {
    try {
      final response = await _httpClient
          .post(
            _uri('/api/messages/send'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phone': phone,
              'name': name,
              'templateName': templateName,
              'templateLanguage': templateLanguage,
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

  /// Gets the current authoritative campaign state.
  Future<Map<String, dynamic>?> getCampaignStatus(String campaignId) async {
    try {
      final response = await _httpClient
          .get(_uri('/api/campaigns/$campaignId/status'))
          .timeout(const Duration(seconds: 5));
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
}
