import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/campaign.dart';
import '../../../data/models/customer.dart';
import '../../../data/models/whatsapp_template.dart';
import '../../../data/repositories/app_repository.dart';

class DirectSendScreen extends StatefulWidget {
  final AppRepository repository;
  final Customer customer;
  final String? initialTemplateId;

  const DirectSendScreen({
    super.key,
    required this.repository,
    required this.customer,
    this.initialTemplateId,
  });

  @override
  State<DirectSendScreen> createState() => _DirectSendScreenState();
}

class _DirectSendScreenState extends State<DirectSendScreen> {
  WhatsAppTemplate? _selectedTemplate;
  final Map<String, TextEditingController> _variableControllers = {};
  bool _isSending = false;
  String? _errorMessage;
  Map<String, dynamic>? _sendResult;

  @override
  void initState() {
    super.initState();
    _initializeTemplate();
  }

  void _initializeTemplate() {
    final repo = widget.repository;
    final isProd = repo.settings.isWhatsAppProductionMode;

    // Pick approved templates for the active mode
    final List<WhatsAppTemplate> availableTemplates;
    if (isProd) {
      availableTemplates = repo.activeApprovedTemplates
          .where((t) => t.isProduction)
          .toList();
    } else {
      availableTemplates = repo.activeApprovedTemplates;
    }

    if (widget.initialTemplateId != null) {
      _selectedTemplate = availableTemplates
          .where((t) => t.id == widget.initialTemplateId || t.name == widget.initialTemplateId)
          .firstOrNull;
    }

    _selectedTemplate ??= availableTemplates.firstOrNull ??
        (isProd ? null : repo.templates.firstOrNull);

    _setupVariableControllers();
  }

  void _setupVariableControllers() {
    for (final controller in _variableControllers.values) {
      controller.dispose();
    }
    _variableControllers.clear();

    if (_selectedTemplate == null) return;

    final vars = _selectedTemplate!.variables;
    final spaName = widget.repository.settings.businessName.isNotEmpty
        ? widget.repository.settings.businessName
        : 'Our Spa & Wellness';

    for (int i = 0; i < vars.length; i++) {
      final varName = vars[i];
      String defaultValue = '';

      final lower = varName.toLowerCase();
      if (lower.contains('name') || lower == '1') {
        defaultValue = widget.customer.name;
      } else if (lower.contains('spa') || lower.contains('business') || lower == '2') {
        defaultValue = spaName;
      } else {
        defaultValue = _selectedTemplate!.exampleValues?[varName] ?? '';
      }

      final controller = TextEditingController(text: defaultValue);
      controller.addListener(() {
        if (mounted) setState(() {});
      });
      _variableControllers[varName] = controller;
    }
  }

  @override
  void dispose() {
    for (final controller in _variableControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> _getResolvedVariables() {
    if (_selectedTemplate == null) return [];
    return _selectedTemplate!.variables.map((v) {
      return _variableControllers[v]?.text.trim() ?? '';
    }).toList();
  }

  String _buildPreviewMessage() {
    if (_selectedTemplate == null) return 'No template selected';

    String text = _selectedTemplate!.localBody;
    final spaName = widget.repository.settings.businessName.isNotEmpty
        ? widget.repository.settings.businessName
        : 'Our Spa';

    text = text
        .replaceAll('{name}', widget.customer.name)
        .replaceAll('{customer_name}', widget.customer.name)
        .replaceAll('{spa_name}', spaName)
        .replaceAll('{business_name}', spaName);

    // Also replace indexed parameters like {{1}}, {{2}} or custom variable names
    final vars = _selectedTemplate!.variables;
    for (int i = 0; i < vars.length; i++) {
      final varKey = vars[i];
      final val = _variableControllers[varKey]?.text.trim() ?? '';
      if (val.isNotEmpty) {
        text = text.replaceAll('{{${i + 1}}}', val);
        text = text.replaceAll('{$varKey}', val);
      }
    }

    return text;
  }

  Future<void> _sendMessage() async {
    if (_selectedTemplate == null) {
      setState(() => _errorMessage = 'Please select a WhatsApp template.');
      return;
    }

    if (widget.customer.isOptedOut) {
      setState(() => _errorMessage = 'Cannot send message: customer has opted out of WhatsApp messages.');
      return;
    }

    // Validate phone number
    final cleanDigits = widget.customer.phone.replaceAll(RegExp(r'\D'), '');
    if (cleanDigits.length < 10) {
      setState(() => _errorMessage = 'Invalid customer phone number: ${widget.customer.phone}');
      return;
    }

    final isProd = widget.repository.settings.isWhatsAppProductionMode;
    final isUtility = _selectedTemplate!.category.toUpperCase() == 'UTILITY';
    final hasConsent = isUtility ? widget.customer.hasUtilityConsent : widget.customer.hasMarketingConsent;

    // Consent safeguard for live production broadcasts
    if (isProd && !hasConsent) {
      setState(() {
        _errorMessage =
            'Opt-in consent required: Live production WhatsApp broadcasts require verified opt-in consent for ${widget.customer.name}. Please record consent first.';
      });
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    final campaignId = 'DIRECT-${DateTime.now().millisecondsSinceEpoch}';
    final recipientsPayload = [
      {
        'localCustomerId': widget.customer.id,
        'name': widget.customer.name,
        'phone': widget.customer.phone,
        'hasConsent': hasConsent,
        'consentCategory': isUtility ? 'utility' : 'marketing',
        'consentRecordedAt': (isUtility
                ? widget.customer.utilityConsentRecordedAt
                : widget.customer.marketingConsentRecordedAt)
            ?.toIso8601String(),
      }
    ];

    try {
      final result = await widget.repository.backendClient.sendCampaign(
        campaignId: campaignId,
        campaignName: 'Direct: ${widget.customer.name}',
        businessName: widget.repository.settings.businessName,
        templateId: _selectedTemplate!.id,
        templateName: _selectedTemplate!.metaTemplateName,
        templateLanguage: _selectedTemplate!.metaLanguage,
        templateVariables: _getResolvedVariables(),
        recipients: recipientsPayload,
        optedOutPhones: widget.repository.optedOutCustomers.map((c) => c.phone).toList(),
        token: widget.repository.authToken,
        mode: isProd ? 'production' : 'test',
      );

      if (!mounted) return;

      if (result['success'] == true) {
        // Record into local repository history
        final now = DateTime.now();
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        final campaign = Campaign(
          id: campaignId,
          name: 'Direct: ${widget.customer.name}',
          month: months[now.month - 1],
          date: now,
          targetAudience: widget.customer.name,
          messageContent: _buildPreviewMessage(),
          recipients: 1,
          messagesSent: 1,
          delivered: 0,
          read: 0,
          failed: 0,
          replied: 0,
          status: 'Sent',
          isRealTest: !isProd,
          mode: isProd ? 'production' : 'test',
          backendCampaignId: campaignId,
          templateName: _selectedTemplate!.metaTemplateName,
        );
        await widget.repository.addCampaign(campaign);

        setState(() {
          _isSending = false;
          _sendResult = result;
        });
      } else {
        final err = result['error'];
        String msg = 'Failed to send message to Meta Cloud API.';
        if (err is Map) {
          msg = err['message'] ?? err['title'] ?? msg;
        } else if (err is String) {
          msg = err;
        }
        setState(() {
          _isSending = false;
          _errorMessage = msg;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _errorMessage = 'Network connection error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isProd = widget.repository.settings.isWhatsAppProductionMode;

    final availableTemplates = isProd
        ? widget.repository.activeApprovedTemplates.where((t) => t.isProduction).toList()
        : widget.repository.activeApprovedTemplates;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Send WhatsApp Message'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: _sendResult != null
            ? _buildSuccessView(isDark)
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Recipient Confirmation Card
                    AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.person_rounded, color: AppColors.primarySage, size: 20),
                              SizedBox(width: 8),
                              Text('Recipient Confirmation', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                            ],
                          ),
                          const Divider(height: 20),
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: AppColors.primarySageContainer,
                                child: Text(
                                  widget.customer.name.isNotEmpty
                                      ? widget.customer.name.substring(0, 1).toUpperCase()
                                      : 'C',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primarySageDark, fontSize: 16),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.customer.name,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.customer.phone,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (widget.customer.isOptedOut)
                                StatusBadge.optedOut()
                              else if (widget.customer.hasMarketingConsent)
                                StatusBadge.marketingConsent()
                              else if (widget.customer.hasUtilityConsent)
                                StatusBadge.utilityConsent()
                              else
                                StatusBadge.noConsent(),
                            ],
                          ),
                          if (widget.customer.isOptedOut) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFEBEE),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.warning_rounded, color: AppColors.error, size: 16),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'This customer has opted out of WhatsApp broadcasts.',
                                      style: TextStyle(fontSize: 11.5, color: AppColors.error, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Template Selection Section
                    Text(
                      'Select Approved WhatsApp Template',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (availableTemplates.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3CD),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          isProd
                              ? 'No approved production templates available. Please sync templates with Meta from the Templates screen.'
                              : 'No approved templates found. Please create or approve a template first.',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF856404)),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.cardDark : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.borderLight),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<WhatsAppTemplate>(
                            isExpanded: true,
                            value: _selectedTemplate,
                            items: availableTemplates.map((t) {
                              return DropdownMenuItem(
                                value: t,
                                child: Text('${t.displayName} (${t.category})'),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedTemplate = val;
                                  _setupVariableControllers();
                                });
                              }
                            },
                          ),
                        ),
                      ),

                    // Template Variables Fields
                    if (_selectedTemplate != null && _selectedTemplate!.variables.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Template Parameters',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._selectedTemplate!.variables.map((varName) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TextField(
                            controller: _variableControllers[varName],
                            decoration: InputDecoration(
                              labelText: 'Parameter: $varName',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        );
                      }),
                    ],

                    const SizedBox(height: 18),

                    // Live Message Preview
                    Text(
                      'Message Preview',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCF8C6),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFC7EBB0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _buildPreviewMessage(),
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF1E3A1A),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Align(
                            alignment: Alignment.bottomRight,
                            child: Text(
                              'Just now • WhatsApp',
                              style: TextStyle(fontSize: 10.5, color: Color(0xFF5A7A54)),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFFCDD2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(fontSize: 12, color: AppColors.error),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Final Send Message Action
                    PrimaryButton(
                      text: _isSending ? 'Sending Message...' : 'Send WhatsApp Message',
                      icon: Icons.send_rounded,
                      isLoading: _isSending,
                      onPressed: (_isSending || widget.customer.isOptedOut || _selectedTemplate == null)
                          ? null
                          : _sendMessage,
                    ),

                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel and Return'),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSuccessView(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: Color(0xFFE8F5E9),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 54),
            ),
            const SizedBox(height: 18),
            Text(
              'Message Sent Successfully',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: isDark ? AppColors.textLight : AppColors.textCharcoal,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your direct message to ${widget.customer.name} (${widget.customer.phone}) has been accepted by Meta WhatsApp Cloud API.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, color: AppColors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              text: 'Return to Contacts',
              icon: Icons.arrow_back_rounded,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
