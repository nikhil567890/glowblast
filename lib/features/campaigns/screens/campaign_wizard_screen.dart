import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/demo_ribbon.dart';
import '../../../core/widgets/app_card.dart';
import '../../../data/models/customer.dart';
import '../../../data/models/campaign.dart';
import '../../../data/repositories/app_repository.dart';
import '../../../data/demo_data/initial_data.dart';
import 'sending_simulation_screen.dart';

class CampaignWizardScreen extends StatefulWidget {
  final AppRepository repository;
  final String? preselectedAudience;
  final String? preselectedTemplateId;

  const CampaignWizardScreen({
    super.key,
    required this.repository,
    this.preselectedAudience,
    this.preselectedTemplateId,
  });

  @override
  State<CampaignWizardScreen> createState() => _CampaignWizardScreenState();
}

class _CampaignWizardScreenState extends State<CampaignWizardScreen> {
  // 4 Steps: 0: Audience, 1: Message, 2: Schedule, 3: Review
  int _currentStep = 0;

  // Step 1: Audience Selection
  // 'All', 'Custom', or a group ID
  String _selectedAudienceType = 'All';
  final Set<String> _customCustomerIds = {};

  // Step 2: Message
  late TextEditingController _campaignNameController;
  late TextEditingController _messageController;
  bool _isGeneratingAi = false;

  // Step 3: Schedule
  bool _isSendNow = true;
  DateTime _scheduledDate = DateTime.now().add(const Duration(days: 2));
  TimeOfDay _scheduledTime = const TimeOfDay(hour: 10, minute: 0);

  @override
  void initState() {
    super.initState();

    final biz = widget.repository.settings.businessName.isNotEmpty
        ? widget.repository.settings.businessName
        : 'our spa';

    String initialTitle = 'Monsoon Glow Offer';
    String initialMsg = '🌸 Monsoon Glow Special! Indulge in our soothing Aromatherapy or Facial with flat 30% OFF this week at $biz. Reply YES to reserve your slot!';

    if (widget.preselectedTemplateId != null) {
      final tpl = InitialData.templates.firstWhere(
        (t) => t['id'] == widget.preselectedTemplateId,
        orElse: () => InitialData.templates.first,
      );
      initialTitle = tpl['title']!;
      initialMsg = tpl['body']!;
    }

    if (widget.preselectedAudience != null) {
      final a = widget.preselectedAudience!;
      if (a == 'All' || a.contains('All')) {
        _selectedAudienceType = 'All';
      } else {
        // Check if matches a group
        final match = widget.repository.groups.where((g) => g.name == a).firstOrNull;
        if (match != null) {
          _selectedAudienceType = match.id;
        } else {
          _selectedAudienceType = 'All';
        }
      }
    }

    _campaignNameController = TextEditingController(text: initialTitle);
    _messageController = TextEditingController(text: initialMsg);
  }

  @override
  void dispose() {
    _campaignNameController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  List<Customer> _calculateSelectedRecipients() {
    final repo = widget.repository;
    if (_selectedAudienceType == 'All') {
      return repo.eligibleCustomers;
    } else if (_selectedAudienceType == 'Custom') {
      return repo.eligibleCustomers.where((c) => _customCustomerIds.contains(c.id)).toList();
    } else {
      // Group selection
      final grp = repo.groups.where((g) => g.id == _selectedAudienceType).firstOrNull;
      if (grp != null) {
        final idSet = grp.customerIds.toSet();
        return repo.eligibleCustomers.where((c) => idSet.contains(c.id)).toList();
      }
      return repo.eligibleCustomers;
    }
  }

  String _getAudienceDisplayLabel() {
    if (_selectedAudienceType == 'All') {
      return 'All Customers';
    } else if (_selectedAudienceType == 'Custom') {
      return 'Custom Selection (${_customCustomerIds.length})';
    } else {
      final grp = widget.repository.groups.where((g) => g.id == _selectedAudienceType).firstOrNull;
      return grp != null ? grp.name : 'Selected Group';
    }
  }

  String _resolveMessagePreview(String text, Customer? sampleCustomer) {
    final customerName = sampleCustomer?.name ?? 'Ananya Sharma';
    final biz = widget.repository.settings.businessName.isNotEmpty
        ? widget.repository.settings.businessName
        : 'Our Spa & Wellness';

    return text
        .replaceAll('{name}', customerName)
        .replaceAll('{customer_name}', customerName)
        .replaceAll('{spa_name}', biz)
        .replaceAll('{business_name}', biz);
  }

  void _generateAiVariations() async {
    setState(() => _isGeneratingAi = true);
    await Future.delayed(const Duration(milliseconds: 600));

    final biz = widget.repository.settings.businessName.isNotEmpty
        ? widget.repository.settings.businessName
        : 'our spa';

    if (!mounted) return;
    setState(() {
      _isGeneratingAi = false;
      _messageController.text =
          '✨ Exclusive Wellness Invitation: Indulge in complete serenity with 30% savings on all luxury sessions this week at $biz. Reply YES to reserve your appointment!';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✓ AI suggestion applied!')),
    );
  }

  void _submitCampaign() async {
    final recipients = _calculateSelectedRecipients();
    if (recipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one recipient.')),
      );
      return;
    }

    final settings = widget.repository.settings;
    if (settings.isWhatsAppTestMode && recipients.length > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WhatsApp Test Mode allows up to 5 authorized recipients.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message content cannot be empty.')),
      );
      return;
    }

    if (_isSendNow) {
      // Navigate to simulation / real send screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => SendingSimulationScreen(
            repository: widget.repository,
            campaignName: _campaignNameController.text.trim(),
            targetAudience: _getAudienceDisplayLabel(),
            messageContent: _messageController.text.trim(),
            selectedCustomers: recipients,
            isRealTest: settings.isWhatsAppTestMode,
          ),
        ),
      );
    } else {
      // Schedule campaign
      final now = DateTime.now();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final fullScheduledDate = DateTime(
        _scheduledDate.year,
        _scheduledDate.month,
        _scheduledDate.day,
        _scheduledTime.hour,
        _scheduledTime.minute,
      );

      final newCampaign = Campaign(
        id: 'sched_${DateTime.now().millisecondsSinceEpoch}',
        name: _campaignNameController.text.trim(),
        month: months[now.month - 1],
        date: now,
        channel: 'WhatsApp',
        targetAudience: _getAudienceDisplayLabel(),
        messageContent: _messageController.text.trim(),
        recipients: recipients.length,
        messagesSent: recipients.length,
        delivered: 0,
        read: 0,
        failed: 0,
        replied: 0,
        status: 'Scheduled',
        scheduledDate: fullScheduledDate,
      );

      await widget.repository.addCampaign(newCampaign);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Campaign "${newCampaign.name}" scheduled for WhatsApp broadcast.'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final recipients = _calculateSelectedRecipients();
    final firstCustomer = recipients.isNotEmpty ? recipients.first : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Campaign Composer'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const DemoRibbon(label: 'WHATSAPP BROADCAST COMPOSER'),

            // 4-Step Progress Indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              color: isDark ? AppColors.surfaceDark : Colors.white,
              child: Row(
                children: [
                  _buildStepBubble(0, 'Audience', isDark),
                  _buildStepDivider(0),
                  _buildStepBubble(1, 'Message', isDark),
                  _buildStepDivider(1),
                  _buildStepBubble(2, 'Schedule', isDark),
                  _buildStepDivider(2),
                  _buildStepBubble(3, 'Review', isDark),
                ],
              ),
            ),

            const Divider(height: 1),

            // Step Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: _buildCurrentStepContent(isDark, recipients, firstCustomer),
              ),
            ),

            // Bottom Navigation Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                border: Border(
                  top: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentStep > 0)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.arrow_back_rounded, size: 16),
                      label: const Text('Back'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onPressed: () => setState(() => _currentStep--),
                    )
                  else
                    const SizedBox.shrink(),

                  if (_currentStep < 3)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                      label: const Text('Next Step'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primarySage,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      onPressed: () {
                        if (_currentStep == 0 && recipients.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please select at least one eligible recipient.')),
                          );
                          return;
                        }
                        if (_currentStep == 1 && _messageController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please write or select a message.')),
                          );
                          return;
                        }
                        setState(() => _currentStep++);
                      },
                    )
                  else
                    ElevatedButton.icon(
                      icon: Icon(_isSendNow ? Icons.send_rounded : Icons.schedule_rounded, size: 16),
                      label: Text(
                        _isSendNow
                            ? (widget.repository.settings.isWhatsAppTestMode
                                ? 'Send Test Campaign'
                                : 'Send Campaign')
                            : 'Confirm Schedule',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (widget.repository.settings.isWhatsAppTestMode && recipients.length > 5)
                            ? Colors.grey
                            : AppColors.primarySage,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      onPressed: (widget.repository.settings.isWhatsAppTestMode && recipients.length > 5)
                          ? () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('WhatsApp Test Mode allows up to 5 authorized recipients.'),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                            }
                          : _submitCampaign,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepBubble(int stepIndex, String title, bool isDark) {
    final isDone = _currentStep > stepIndex;
    final isActive = _currentStep == stepIndex;

    Color circleColor = isDark ? AppColors.borderDark : Colors.grey.shade200;
    Color textColor = isDark ? AppColors.textMutedDark : AppColors.textMuted;
    Color iconColor = Colors.grey;

    if (isActive) {
      circleColor = AppColors.primarySage;
      textColor = isDark ? AppColors.textLight : AppColors.primarySage;
      iconColor = Colors.white;
    } else if (isDone) {
      circleColor = AppColors.primarySageContainer;
      textColor = AppColors.primarySageDark;
      iconColor = AppColors.primarySageDark;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: circleColor,
          child: isDone
              ? Icon(Icons.check_rounded, size: 14, color: iconColor)
              : Text(
                  '${stepIndex + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isActive ? Colors.white : (isDone ? AppColors.primarySageDark : textColor),
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
            color: textColor,
          ),
        ),
      ],
    );
  }

  Widget _buildStepDivider(int fromStep) {
    final isPassed = _currentStep > fromStep;
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 16, left: 4, right: 4),
        color: isPassed ? AppColors.primarySage : Colors.grey.shade300,
      ),
    );
  }

  Widget _buildCurrentStepContent(bool isDark, List<Customer> recipients, Customer? firstCustomer) {
    switch (_currentStep) {
      case 0:
        return _buildStep1Audience(isDark, recipients);
      case 1:
        return _buildStep2Message(isDark, firstCustomer);
      case 2:
        return _buildStep3Schedule(isDark);
      case 3:
      default:
        return _buildStep4Review(isDark, recipients, firstCustomer);
    }
  }

  // --- Step 1: Audience ---
  Widget _buildStep1Audience(bool isDark, List<Customer> recipients) {
    final repo = widget.repository;
    final groups = repo.groups;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step 1: Choose Your Audience',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: isDark ? AppColors.textLight : AppColors.textCharcoal,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Select who will receive this WhatsApp message. Opted-out contacts (${repo.optedOutCustomersCount}) are strictly excluded automatically.',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 18),

        // Option 1: All Customers
        _buildAudienceCard(
          title: 'All Eligible Customers',
          subtitle: '${repo.eligibleCustomersCount} clients ready to receive broadcast',
          icon: Icons.people_alt_rounded,
          isSelected: _selectedAudienceType == 'All',
          onTap: () => setState(() => _selectedAudienceType = 'All'),
          isDark: isDark,
        ),

        const SizedBox(height: 10),

        // User-Created Groups
        ...groups.map((g) {
          final groupCount = repo.eligibleCustomers.where((c) => g.customerIds.contains(c.id)).length;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildAudienceCard(
              title: g.name,
              subtitle: '$groupCount eligible clients • ${g.description}',
              icon: Icons.folder_special_rounded,
              isSelected: _selectedAudienceType == g.id,
              onTap: () => setState(() => _selectedAudienceType = g.id),
              isDark: isDark,
            ),
          );
        }),

        // Option 3: Custom Selection
        _buildAudienceCard(
          title: 'Custom Selection',
          subtitle: _customCustomerIds.isEmpty
              ? 'Hand-pick specific recipients from directory'
              : '${_customCustomerIds.length} recipients selected',
          icon: Icons.checklist_rounded,
          isSelected: _selectedAudienceType == 'Custom',
          onTap: () => setState(() => _selectedAudienceType = 'Custom'),
          isDark: isDark,
        ),

        if (_selectedAudienceType == 'Custom') ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.cardDark : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select Customers (${_customCustomerIds.length} picked)',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          if (_customCustomerIds.length == repo.eligibleCustomers.length) {
                            _customCustomerIds.clear();
                          } else {
                            _customCustomerIds.addAll(repo.eligibleCustomers.map((c) => c.id));
                          }
                        });
                      },
                      child: Text(
                        _customCustomerIds.length == repo.eligibleCustomers.length ? 'Clear All' : 'Select All',
                      ),
                    ),
                  ],
                ),
                const Divider(),
                SizedBox(
                  height: 220,
                  child: ListView.builder(
                    itemCount: repo.eligibleCustomers.length,
                    itemBuilder: (context, index) {
                      final c = repo.eligibleCustomers[index];
                      final isChecked = _customCustomerIds.contains(c.id);
                      return CheckboxListTile(
                        dense: true,
                        value: isChecked,
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        subtitle: Text(c.phone, style: const TextStyle(fontSize: 12)),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _customCustomerIds.add(c.id);
                            } else {
                              _customCustomerIds.remove(c.id);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),

        // Summary Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primarySageContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.primarySageDark, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${recipients.length} eligible recipients selected for this WhatsApp blast.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primarySageDark,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAudienceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppColors.primarySageDark.withValues(alpha: 0.35) : AppColors.primarySageContainer.withValues(alpha: 0.7))
              : (isDark ? AppColors.cardDark : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primarySage : (isDark ? AppColors.borderDark : AppColors.borderLight),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primarySage : (isDark ? AppColors.surfaceDark : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: isSelected ? Colors.white : AppColors.textMuted, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: isDark ? AppColors.textMutedDark : AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: isSelected ? AppColors.primarySage : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  // --- Step 2: Message ---
  Widget _buildStep2Message(bool isDark, Customer? sampleCustomer) {
    final previewResolved = _resolveMessagePreview(_messageController.text, sampleCustomer);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step 2: Compose Message',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: isDark ? AppColors.textLight : AppColors.textCharcoal,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Customize your promotional copy. Use tags for instant personalization.',
          style: TextStyle(fontSize: 13, color: isDark ? AppColors.textMutedDark : AppColors.textMuted),
        ),
        const SizedBox(height: 18),

        // Campaign Name
        const Text('Campaign Name', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        const SizedBox(height: 6),
        TextField(
          controller: _campaignNameController,
          decoration: InputDecoration(
            hintText: 'e.g. Festive Glow Special',
            filled: true,
            fillColor: isDark ? AppColors.cardDark : Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),

        const SizedBox(height: 18),

        // Message text box header & tags
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('WhatsApp Message', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            TextButton.icon(
              icon: _isGeneratingAi
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_rounded, size: 15, color: AppColors.accentGold),
              label: const Text('AI Rewrite', style: TextStyle(fontSize: 12, color: AppColors.accentGold, fontWeight: FontWeight.w700)),
              onPressed: _isGeneratingAi ? null : _generateAiVariations,
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _messageController,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Write your broadcast message here...',
            filled: true,
            fillColor: isDark ? AppColors.cardDark : Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),

        const SizedBox(height: 8),

        // Personalization tags chips
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.add, size: 14),
              label: const Text('{name}'),
              labelStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              onPressed: () {
                _messageController.text += ' {name}';
                setState(() {});
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 14),
              label: const Text('{business_name}'),
              labelStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              onPressed: () {
                _messageController.text += ' {business_name}';
                setState(() {});
              },
            ),
          ],
        ),

        const SizedBox(height: 22),

        // WhatsApp Live Preview
        Row(
          children: [
            const Icon(Icons.chat_rounded, color: AppColors.whatsApp, size: 18),
            const SizedBox(width: 6),
            Text(
              'WhatsApp Preview (${sampleCustomer?.name ?? "Recipient"})',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // WhatsApp Chat Bubble
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F1A15) : const Color(0xFFE5DDD5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? AppColors.borderDark : Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 320),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E2D24) : Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                    bottomRight: Radius.circular(14),
                    bottomLeft: Radius.circular(3),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      previewResolved,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          DateFormat('hh:mm a').format(DateTime.now()),
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.done_all_rounded, size: 14, color: Color(0xFF34B7F1)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  // --- Step 3: Schedule ---
  Widget _buildStep3Schedule(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step 3: Schedule Dispatch',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: isDark ? AppColors.textLight : AppColors.textCharcoal,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Choose whether to broadcast right away or schedule for an optimal time slot.',
          style: TextStyle(fontSize: 13, color: isDark ? AppColors.textMutedDark : AppColors.textMuted),
        ),
        const SizedBox(height: 20),

        // Send Immediately Option
        _buildScheduleOptionCard(
          title: 'Send Immediately',
          subtitle: 'Simulate instant dispatch to all eligible clients',
          icon: Icons.flash_on_rounded,
          isSelected: _isSendNow,
          onTap: () => setState(() => _isSendNow = true),
          isDark: isDark,
        ),

        const SizedBox(height: 12),

        // Schedule for Later Option
        _buildScheduleOptionCard(
          title: 'Schedule for Later Date & Time',
          subtitle: 'Automate broadcast for peak engagement windows',
          icon: Icons.calendar_today_rounded,
          isSelected: !_isSendNow,
          onTap: () => setState(() => _isSendNow = false),
          isDark: isDark,
        ),

        if (!_isSendNow) ...[
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pick Date & Time', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_month_rounded, size: 16),
                        label: Text(DateFormat('dd MMM yyyy').format(_scheduledDate)),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _scheduledDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 90)),
                          );
                          if (picked != null) {
                            setState(() => _scheduledDate = picked);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.access_time_rounded, size: 16),
                        label: Text(_scheduledTime.format(context)),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _scheduledTime,
                          );
                          if (picked != null) {
                            setState(() => _scheduledTime = picked);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildScheduleOptionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppColors.primarySageDark.withValues(alpha: 0.35) : AppColors.primarySageContainer.withValues(alpha: 0.7))
              : (isDark ? AppColors.cardDark : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primarySage : (isDark ? AppColors.borderDark : AppColors.borderLight),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primarySage : (isDark ? AppColors.surfaceDark : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: isSelected ? Colors.white : AppColors.textMuted, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: isDark ? AppColors.textMutedDark : AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: isSelected ? AppColors.primarySage : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  // --- Step 4: Review ---
  Widget _buildStep4Review(bool isDark, List<Customer> recipients, Customer? firstCustomer) {
    final settings = widget.repository.settings;
    final totalCount = recipients.length; // 1 customer = 1 message
    final previewResolved = _resolveMessagePreview(_messageController.text, firstCustomer);
    final hasEnoughCredits = settings.whatsAppCredits >= totalCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step 4: Review & Dispatch',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: isDark ? AppColors.textLight : AppColors.textCharcoal,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Confirm your campaign parameters before broadcasting.',
          style: TextStyle(fontSize: 13, color: isDark ? AppColors.textMutedDark : AppColors.textMuted),
        ),
        const SizedBox(height: 18),

        // Campaign Overview Card
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Campaign Overview', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const Divider(height: 18),
              _buildReviewRow('Campaign Name', _campaignNameController.text.trim()),
              const SizedBox(height: 8),
              _buildReviewRow('Channel', 'WhatsApp Business', isSuccess: true),
              const SizedBox(height: 8),
              _buildReviewRow('Target Audience', _getAudienceDisplayLabel()),
              const SizedBox(height: 8),
              _buildReviewRow('Total Recipients', '$totalCount clients ($totalCount messages)'),
              const SizedBox(height: 8),
              _buildReviewRow('Sender Business', settings.businessName.isNotEmpty ? settings.businessName : 'Spa & Wellness'),
              const SizedBox(height: 8),
              _buildReviewRow(
                'Schedule',
                _isSendNow
                    ? 'Send Immediately'
                    : DateFormat('dd MMM yyyy, hh:mm a').format(
                        DateTime(
                          _scheduledDate.year,
                          _scheduledDate.month,
                          _scheduledDate.day,
                          _scheduledTime.hour,
                          _scheduledTime.minute,
                        ),
                      ),
              ),
              if (settings.isWhatsAppTestMode) ...[
                const SizedBox(height: 8),
                _buildReviewRow('Mode', 'WhatsApp Test Mode (Real API)', isSuccess: true),
                const SizedBox(height: 8),
                _buildReviewRow('Test Display Number', '+1 (555) 632-5494'),
              ],
            ],
          ),
        ),

        if (settings.isWhatsAppTestMode && totalCount > 5) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEECEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'WhatsApp Test Mode allows up to 5 authorized recipients. Please select "Custom Selection" in Step 1 to choose up to 5 authorized test numbers.',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),

        // WhatsApp Preview
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.chat_rounded, color: AppColors.whatsApp, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Resolved Message Preview (${firstCustomer?.name ?? "Client"})',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E2D24) : AppColors.whatsAppBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  previewResolved,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white : Colors.black87,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Credits balance check card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: hasEnoughCredits ? AppColors.primarySageContainer : const Color(0xFFFEECEB),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                hasEnoughCredits ? Icons.check_circle_rounded : Icons.warning_rounded,
                color: hasEnoughCredits ? AppColors.primarySageDark : AppColors.error,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasEnoughCredits
                      ? 'Sufficient balance: $totalCount WhatsApp credits required. Wallet balance: ${settings.whatsAppCredits} credits.'
                      : 'Insufficient demo credits ($totalCount needed, ${settings.whatsAppCredits} available). Please recharge in Settings.',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: hasEnoughCredits ? AppColors.primarySageDark : AppColors.error,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildReviewRow(String label, String value, {bool isSuccess = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isSuccess ? AppColors.whatsApp : null,
            ),
          ),
        ),
      ],
    );
  }
}
