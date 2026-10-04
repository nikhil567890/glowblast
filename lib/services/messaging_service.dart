import 'dart:async';
import 'glowblast_backend_client.dart';

class SendResult {
  final bool isSuccess;
  final String messageId;
  final String status;
  final String? error;
  final DateTime timestamp;

  SendResult({
    required this.isSuccess,
    required this.messageId,
    required this.status,
    this.error,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

abstract class MessagingService {
  Future<SendResult> sendMessage({
    required String recipientPhone,
    required String recipientName,
    required String content,
  });
}

/// Simulated Demo Messaging Service (Local-first, WhatsApp only)
class DemoMessagingService implements MessagingService {
  @override
  Future<SendResult> sendMessage({
    required String recipientPhone,
    required String recipientName,
    required String content,
  }) async {
    // Artificial slight delay to simulate local packet
    await Future.delayed(const Duration(milliseconds: 10));

    return SendResult(
      isSuccess: true,
      messageId: 'DEMO_WHATSAPP_${DateTime.now().millisecondsSinceEpoch}',
      status: 'Prepared',
    );
  }
}

/// Real WhatsApp Messaging Service that connects through the secure GlowBlast backend.
/// NEVER calls Meta directly.
class RealWhatsAppMessagingService implements MessagingService {
  final GlowBlastBackendClient backendClient;

  RealWhatsAppMessagingService({required this.backendClient});

  @override
  Future<SendResult> sendMessage({
    required String recipientPhone,
    required String recipientName,
    required String content,
  }) async {
    final res = await backendClient.sendSingleMessage(
      phone: recipientPhone,
      name: recipientName,
      templateName: 'hello_world',
      templateLanguage: 'en_US',
    );

    if (res['success'] == true) {
      return SendResult(
        isSuccess: true,
        messageId: res['providerMessageId']?.toString() ?? 'GB_ACCEPTED',
        status: 'accepted',
      );
    } else {
      final err = res['error'];
      final msg = err is Map ? (err['message'] ?? err['title'] ?? 'Send failed') : 'Could not dispatch via backend';
      return SendResult(
        isSuccess: false,
        messageId: '',
        status: 'failed',
        error: msg.toString(),
      );
    }
  }
}

/// Future Production WhatsApp Provider interface (plugs in later)
abstract class OfficialWhatsAppProvider {
  Future<SendResult> sendWhatsAppTemplate({
    required String templateName,
    required String phone,
    required Map<String, String> parameters,
  });
}
