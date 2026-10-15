import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/demo_ribbon.dart';
import '../../../data/models/campaign.dart';
import '../../../data/models/customer.dart';
import '../../../data/repositories/app_repository.dart';
import 'campaign_success_screen.dart';

class SendingSimulationScreen extends StatefulWidget {
  final AppRepository repository;
  final String campaignName;
  final String targetAudience;
  final String messageContent;
  final List<Customer> selectedCustomers;
  final bool isRealTest;
  final String templateName;
  final String templateLanguage;
  final String? templateId;
  final List<String> templateVariables;
  final String templateCategory;
  final String messagingMode; // 'demo', 'test', 'production'

  const SendingSimulationScreen({
    super.key,
    required this.repository,
    required this.campaignName,
    required this.targetAudience,
    required this.messageContent,
    required this.selectedCustomers,
    this.isRealTest = false,
    this.messagingMode = 'test',
    required this.templateName,
    this.templateLanguage = 'en_US',
    this.templateId,
    this.templateVariables = const [],
    this.templateCategory = 'MARKETING',
  });

  bool get isProduction => messagingMode == 'production';
  bool get isRealDispatch => isProduction || messagingMode == 'test' || isRealTest;

  @override
  State<SendingSimulationScreen> createState() => _SendingSimulationScreenState();
}

class _SendingSimulationScreenState extends State<SendingSimulationScreen> {
  int _currentStep = 0; // 0: audience, 1: personalizing, 2: validating, 3: sending
  int _sentCounter = 0;
  int _totalToSend = 0;
  double _progress = 0.0;
  Timer? _timer;
  StreamSubscription? _sseSubscription;

  // Real WhatsApp test state
  bool _hasError = false;
  String? _errorMessage;
  int _acceptedCount = 0;
  int _deliveredCount = 0;
  int _readCount = 0;
  int _failedCount = 0;
  String _currentRecipientStatus = 'Connecting to backend...';

  @override
  void initState() {
    super.initState();
    // Strictly exclude any opted-out customers, and enforce opt-in consent for production
    final isUtility = widget.templateCategory.toUpperCase() == 'UTILITY';
    final eligible = widget.selectedCustomers.where((c) {
      if (c.isOptedOut) return false;
      if (widget.isProduction) {
        return isUtility ? c.hasUtilityConsent : c.hasMarketingConsent;
      }
      return true;
    }).toList();
    _totalToSend = eligible.length; // 1 customer = 1 message

    if (widget.isRealDispatch && widget.messagingMode != 'demo') {
      _startRealWhatsAppSending(eligible);
    } else {
      _startSimulation(eligible);
    }
  }

  // --- Real WhatsApp Cloud API Dispatch Path ---
  void _startRealWhatsAppSending(List<Customer> eligible) async {
    setState(() {
      _currentStep = 1;
      _currentRecipientStatus = widget.isProduction
          ? 'Validating production recipients and opt-in consent...'
          : 'Validating recipients against authorized test allowlist...';
    });

    final campaignId = 'GB-${DateTime.now().millisecondsSinceEpoch}';

    // Convert eligible customers to backend payload with consent flags
    final isUtility = widget.templateCategory.toUpperCase() == 'UTILITY';
    final recipientsPayload = eligible.map((c) {
      return {
        'localCustomerId': c.id,
        'name': c.name,
        'phone': c.phone,
        'hasConsent': isUtility ? c.hasUtilityConsent : c.hasMarketingConsent,
        'consentCategory': isUtility ? 'utility' : 'marketing',
        'consentRecordedAt': (isUtility ? c.utilityConsentRecordedAt : c.marketingConsentRecordedAt)?.toIso8601String(),
      };
    }).toList();

    // 1. Call backend send endpoint first with selected template and active JWT
    final sendResult = await widget.repository.backendClient.sendCampaign(
      campaignId: campaignId,
      campaignName: widget.campaignName,
      businessName: widget.repository.settings.businessName,
      templateId: widget.templateId,
      templateName: widget.templateName,
      templateLanguage: widget.templateLanguage,
      templateVariables: widget.templateVariables,
      recipients: recipientsPayload,
      optedOutPhones: widget.repository.optedOutCustomers.map((c) => c.phone).toList(),
      token: widget.repository.authToken,
      mode: widget.isProduction ? 'production' : 'test',
    );

    if (!mounted) return;

    if (sendResult['success'] != true) {
      final statusCode = sendResult['statusCode'] as int?;
      final err = sendResult['error'];
      String msg = 'Failed to submit campaign to backend.';

      if (statusCode == 401 || (err is Map && err['code'] == 'UNAUTHORIZED')) {
        msg = 'Authentication required. Please sign in again.';
      } else if (statusCode == 403 || (err is Map && err['code'] == 'FORBIDDEN')) {
        msg = 'You are not authorized to send this campaign.';
      } else if (statusCode == 404 || (err is Map && err['code'] == 'NOT_FOUND')) {
        msg = 'Campaign service endpoint not found.';
      } else if (statusCode != null && statusCode >= 500) {
        msg = 'Campaign service temporarily unavailable. Please try again.';
      } else if (err is Map) {
        final code = err['code'];
        final errText = err['message'] ?? err['title'];
        final fields = err['fields'];
        if (code == 131031 || code == '131031') {
          msg = 'WhatsApp Business Account is restricted. Meta rejected this message.';
        } else if (code == 'PRODUCTION_MODE_DISABLED') {
          msg = 'Live production campaigns are disabled on the backend (ENABLE_PRODUCTION_CAMPAIGNS=false). Safe fail-closed protection active.';
        } else if (code == 'UNAUTHORIZED_PRODUCTION_USER') {
          msg = 'Your user account email is not authorized for live production broadcasts (PRODUCTION_ALLOWED_EMAILS).';
        } else if (code == 'DAILY_RECIPIENT_LIMIT_EXCEEDED') {
          msg = errText ?? 'Daily 24-hour production recipient limit exceeded (max 200 unique recipients).';
        } else if (code == 'NO_ELIGIBLE_CONSENTED_RECIPIENTS') {
          msg = 'No eligible consented recipients found. In compliance with WhatsApp policies, live broadcasts require documented customer opt-in.';
        } else if (code == 'INVALID_PRODUCTION_TEMPLATE') {
          msg = 'The test-only hello_world fixture cannot be used for production campaigns. Please choose an approved production template.';
        } else if (code == 'PRODUCTION_CREDENTIALS_MISSING') {
          msg = 'Production WhatsApp Cloud API credentials are not configured on Render.';
        } else if (code == 'TEST_RECIPIENT_LIMIT') {
          msg = errText ?? 'WhatsApp Test Mode allows up to 5 authorized recipients.';
        } else if (code == 'TEMPLATE_NOT_APPROVED') {
          msg = errText ?? 'This template is not approved for WhatsApp broadcast.';
        } else if (code == 'VALIDATION_ERROR' && fields is List && fields.isNotEmpty) {
          msg = 'Invalid campaign data: ${fields.join(', ')}';
        } else {
          msg = errText ?? msg;
        }
      }

      setState(() {
        _hasError = true;
        _errorMessage = msg;
      });
      return;
    }

    // 2. Connect to real-time SSE event stream only after backend accepts campaign
    try {
      _sseSubscription = widget.repository.backendClient
          .connectToCampaignEvents(campaignId)
          .listen((event) {
        if (!mounted) return;

        final eventType = event['type'] ?? event['eventType'];

        if (eventType == 'message_status') {
          final phone = event['phone']?.toString() ?? '';
          final status = event['status']?.toString() ?? '';
          setState(() {
            _currentRecipientStatus = 'Recipient $phone: $status';
          });
        } else if (eventType == 'campaign_progress') {
          final total = (event['total'] as num?)?.toInt() ?? _totalToSend;
          final accepted = (event['accepted'] as num?)?.toInt() ?? 0;
          final sent = (event['sent'] as num?)?.toInt() ?? 0;
          final delivered = (event['delivered'] as num?)?.toInt() ?? 0;
          final read = (event['read'] as num?)?.toInt() ?? 0;
          final failed = (event['failed'] as num?)?.toInt() ?? 0;
          final processed = accepted + failed;

          setState(() {
            _currentStep = 3;
            _totalToSend = total;
            _acceptedCount = accepted;
            _sentCounter = sent;
            _deliveredCount = delivered;
            _readCount = read;
            _failedCount = failed;
            _progress = total > 0 ? (processed / total).clamp(0.0, 1.0) : 0.0;
          });
        }
      });
    } catch (_) {
      // SSE connection error; polling fallback available
    }

    // Wait for dispatch execution to complete
    int checks = 0;
    String finalStatus = 'processing';
    while (checks < 30) {
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!mounted) return;

      final statusCheck = await widget.repository.backendClient.getCampaignStatus(campaignId);
      if (statusCheck != null) {
        final camp = (statusCheck['campaign'] ?? statusCheck) as Map<String, dynamic>;
        final status = camp['status']?.toString() ?? 'processing';
        final accepted = (camp['accepted'] as num?)?.toInt() ?? _acceptedCount;
        final sent = (camp['sent'] as num?)?.toInt() ?? 0;
        final delivered = (camp['delivered'] as num?)?.toInt() ?? 0;
        final read = (camp['read'] as num?)?.toInt() ?? 0;
        final failed = (camp['failed'] as num?)?.toInt() ?? 0;

        finalStatus = status;

        setState(() {
          _currentStep = 3;
          _acceptedCount = accepted;
          _sentCounter = sent;
          _deliveredCount = delivered;
          _readCount = read;
          _failedCount = failed;
          final processed = accepted + failed;
          _progress = _totalToSend > 0 ? (processed / _totalToSend).clamp(0.0, 1.0) : 1.0;
        });

        // Stop polling immediately when terminal status is reached
        if (status == 'completed' || status == 'completed_with_errors' || status == 'failed') {
          break;
        }
      }
      checks++;
    }

    _completeRealWhatsAppCampaign(campaignId, eligible, finalStatus);
  }

  void _completeRealWhatsAppCampaign(String campaignId, List<Customer> eligible, String finalStatus) async {
    if (!mounted) return;

    final now = DateTime.now();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    // If all recipients failed (e.g. accepted == 0, failed > 0 or finalStatus == 'failed')
    if (finalStatus == 'failed' || (_acceptedCount == 0 && _totalToSend > 0)) {
      String failureReason = 'Recipient is not authorized for the current Meta WhatsApp test environment.';
      try {
        final details = await widget.repository.backendClient.getCampaignDetails(campaignId);
        if (details != null && details['campaign'] != null) {
          final msgs = details['campaign']['messages'] as List<dynamic>?;
          if (msgs != null && msgs.isNotEmpty) {
            final firstFailed = msgs.firstWhere(
              (m) => m['status'] == 'failed',
              orElse: () => null,
            );
            if (firstFailed != null && firstFailed['errorMessage'] != null) {
              failureReason = firstFailed['errorMessage'].toString();
            }
          }
        }
      } catch (_) {}

      final failedCampaign = Campaign(
        id: campaignId,
        name: widget.campaignName,
        month: months[now.month - 1],
        date: now,
        channel: 'WhatsApp',
        targetAudience: widget.targetAudience,
        messageContent: widget.messageContent,
        recipients: eligible.length,
        accepted: 0,
        messagesSent: 0,
        delivered: 0,
        read: 0,
        failed: _failedCount > 0 ? _failedCount : eligible.length,
        replied: 0,
        status: 'Failed',
        isRealTest: !widget.isProduction && (widget.isRealTest || widget.messagingMode == 'test'),
        mode: widget.isProduction ? 'production' : (widget.messagingMode == 'test' ? 'test' : 'demo'),
        backendCampaignId: campaignId,
        templateName: widget.templateName,
      );

      await widget.repository.addCampaign(
        failedCampaign,
        recipientCustomerIds: eligible.map((c) => c.id).toList(),
      );

      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'Message not sent.\n\n$failureReason\n\nAction: Ensure recipient phone numbers are eligible and authorized.';
      });
      return;
    }

    // Determine normalized campaign status for local repository
    String appCampaignStatus = 'Sent';
    if (finalStatus == 'completed_with_errors' || _failedCount > 0) {
      appCampaignStatus = 'Completed with Errors';
    } else if (finalStatus == 'completed') {
      appCampaignStatus = 'Completed';
    }

    final newCampaign = Campaign(
      id: campaignId,
      name: widget.campaignName,
      month: months[now.month - 1],
      date: now,
      channel: 'WhatsApp',
      targetAudience: widget.targetAudience,
      messageContent: widget.messageContent,
      recipients: eligible.length,
      accepted: _acceptedCount,
      messagesSent: _sentCounter, // STRICTLY real sent counter confirmed by backend
      delivered: _deliveredCount,
      read: _readCount,
      failed: _failedCount,
      replied: 0,
      status: appCampaignStatus,
      isRealTest: !widget.isProduction && (widget.isRealTest || widget.messagingMode == 'test'),
      mode: widget.isProduction ? 'production' : (widget.messagingMode == 'test' ? 'test' : 'demo'),
      backendCampaignId: campaignId,
      templateName: widget.templateName,
    );

    // Save real campaign to local repository
    await widget.repository.addCampaign(
      newCampaign,
      recipientCustomerIds: eligible.map((c) => c.id).toList(),
    );

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => CampaignSuccessScreen(
          repository: widget.repository,
          campaign: newCampaign,
        ),
      ),
    );
  }


  // --- Demo Simulation Path (Kept for offline demo mode) ---
  void _startSimulation(List<Customer> eligible) async {
    // Stage 1: Audience check
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _currentStep = 1);

    // Stage 2: Personalization
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _currentStep = 2);

    // Stage 3: Validation
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _currentStep = 3);

    // Stage 4: Animated sending counter
    const totalTicks = 20;
    final tickDuration = Duration(milliseconds: 1400 ~/ totalTicks);
    int currentTick = 0;

    _timer = Timer.periodic(tickDuration, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      currentTick++;
      final ratio = currentTick / totalTicks;
      setState(() {
        _sentCounter = (ratio * _totalToSend).toInt().clamp(0, _totalToSend);
        _progress = ratio.clamp(0.0, 1.0);
      });

      if (currentTick >= totalTicks) {
        timer.cancel();
        _completeSimulation(eligible);
      }
    });
  }

  void _completeSimulation(List<Customer> eligible) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    final messagesTotal = eligible.length;
    final delivered = (messagesTotal * 0.965).round().clamp(1, messagesTotal);
    final failed = messagesTotal - delivered;
    final read = (delivered * 0.72).round().clamp(0, delivered);
    final replied = (read * 0.35).round().clamp(0, read);

    final now = DateTime.now();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    final newCampaign = Campaign(
      id: 'camp_${DateTime.now().millisecondsSinceEpoch}',
      name: widget.campaignName,
      month: months[now.month - 1],
      date: now,
      channel: 'WhatsApp',
      targetAudience: widget.targetAudience,
      messageContent: widget.messageContent,
      recipients: eligible.length,
      messagesSent: messagesTotal,
      delivered: delivered,
      read: read,
      failed: failed,
      replied: replied,
      status: 'Sent',
      isRealTest: false,
    );

    await widget.repository.addCampaign(
      newCampaign,
      recipientCustomerIds: eligible.map((c) => c.id).toList(),
    );

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => CampaignSuccessScreen(
          repository: widget.repository,
          campaign: newCampaign,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sseSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            DemoRibbon(
              label: widget.isProduction
                  ? 'META CLOUD API • LIVE PRODUCTION BROADCAST (+91 95022 59203)'
                  : (widget.isRealDispatch && widget.messagingMode != 'demo'
                      ? 'META CLOUD API • REAL WHATSAPP TEST DISPATCH'
                      : 'DISPATCHING SIMULATION • WHATSAPP ONLY'),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                  child: _hasError
                      ? _buildErrorView(isDark)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Animated WhatsApp broadcast indicator
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.whatsAppBg,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.whatsApp.withValues(alpha: 0.25),
                                    blurRadius: 24,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.chat_rounded,
                                  size: 52,
                                  color: AppColors.whatsApp,
                                ),
                              ),
                            ),

                            const SizedBox(height: 28),

                            Text(
                              widget.isRealTest
                                  ? 'Broadcasting via Meta Cloud API...'
                                  : (_currentStep < 3 ? 'Preparing WhatsApp Broadcast...' : 'Broadcasting Messages...'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                              ),
                            ),

                            const SizedBox(height: 8),

                            Text(
                              widget.isRealTest
                                  ? 'Campaign: "${widget.campaignName}" • Meta Template: "${widget.templateName}" (${widget.templateLanguage})'
                                  : (_currentStep < 3
                                      ? 'Preparing personalized templates for $_totalToSend recipients'
                                      : 'Sending $_sentCounter / $_totalToSend WhatsApp messages...'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primarySage,
                              ),
                            ),

                            if (widget.isRealTest) ...[
                              const SizedBox(height: 10),
                              Text(
                                _currentRecipientStatus,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],

                            const SizedBox(height: 28),

                            // Progress Bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: _progress,
                                minHeight: 12,
                                backgroundColor: isDark ? AppColors.borderDark : Colors.grey.shade200,
                                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.whatsApp),
                              ),
                            ),

                            const SizedBox(height: 12),

                            if (widget.isRealTest) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Meta Accepted: $_acceptedCount',
                                    style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                                  ),
                                  Text(
                                    '${(_progress * 100).toInt()}%',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primarySage,
                                    ),
                                  ),
                                  Text(
                                    'Sent: $_sentCounter · Failed: $_failedCount',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: _failedCount > 0 ? AppColors.error : AppColors.whatsApp,
                                    ),
                                  ),
                                ],
                              ),
                              if (_deliveredCount > 0) ...[
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    'Delivered: $_deliveredCount · Read: $_readCount',
                                    style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ] else ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Dispatched',
                                    style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                                  ),
                                  Text(
                                    '${(_progress * 100).toInt()}%',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primarySage,
                                    ),
                                  ),
                                  Text(
                                    '$_sentCounter / $_totalToSend Sent',
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ],


                            const SizedBox(height: 36),

                            // Checklist
                            _buildStepCheck(
                              stepIndex: 0,
                              label: 'Audience Verified (Opt-Outs Filtered)',
                              isPassed: _currentStep >= 0,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 12),
                            _buildStepCheck(
                              stepIndex: 1,
                              label: widget.isRealTest ? 'Meta Test Allowlist Enforced' : 'WhatsApp Personalization Resolved',
                              isPassed: _currentStep >= 1,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 12),
                            _buildStepCheck(
                              stepIndex: 2,
                              label: widget.isRealTest ? 'Connecting to Backend & Cloud API' : '10-Digit Mobile Compliance Verified',
                              isPassed: _currentStep >= 2,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 12),
                            _buildStepCheck(
                              stepIndex: 3,
                              label: widget.isRealTest ? 'Official Meta API Acceptance' : 'Live WhatsApp Broadcast Stream',
                              isPassed: _currentStep >= 3,
                              isDark: isDark,
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: const BoxDecoration(
            color: Color(0xFFFFEBEE),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Campaign Dispatch Error',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.error),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _errorMessage ?? 'An unexpected error occurred while contacting the Meta WhatsApp API.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 28),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primarySage,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: const Text('Back to Campaign Composer'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildStepCheck({
    required int stepIndex,
    required String label,
    required bool isPassed,
    required bool isDark,
  }) {
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isPassed ? AppColors.whatsApp : (isDark ? AppColors.borderDark : Colors.grey.shade300),
          ),
          child: Center(
            child: isPassed
                ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                : const SizedBox.shrink(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isPassed ? FontWeight.w700 : FontWeight.w500,
              color: isPassed
                  ? (isDark ? AppColors.textLight : AppColors.textCharcoal)
                  : AppColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}
