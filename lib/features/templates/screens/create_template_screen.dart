import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../data/models/whatsapp_template.dart';
import '../../../data/repositories/app_repository.dart';

class CreateTemplateScreen extends StatefulWidget {
  final AppRepository repository;

  const CreateTemplateScreen({super.key, required this.repository});

  @override
  State<CreateTemplateScreen> createState() => _CreateTemplateScreenState();
}

class _CreateTemplateScreenState extends State<CreateTemplateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _bodyController = TextEditingController();

  String _category = 'MARKETING';
  String _language = 'en_US';
  bool _isSubmitting = false;

  final List<String> _suggestedVariables = ['name', 'business_name', 'offer', 'date'];

  @override
  void initState() {
    super.initState();
    _bodyController.addListener(() => setState(() {}));
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _displayNameController.dispose();
    _descriptionController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  List<String> _extractVariables(String text) {
    final matches = RegExp(r'\{([a-zA-Z0-9_]+)\}').allMatches(text);
    final Set<String> vars = {};
    for (final m in matches) {
      if (m.group(1) != null) {
        vars.add(m.group(1)!);
      }
    }
    return vars.toList();
  }

  void _insertVariable(String varName) {
    final text = _bodyController.text;
    final selection = _bodyController.selection;
    final tag = '{$varName}';

    if (selection.isValid && selection.start >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, tag);
      _bodyController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + tag.length),
      );
    } else {
      _bodyController.text = '$text $tag';
      _bodyController.selection = TextSelection.collapsed(offset: _bodyController.text.length);
    }
  }

  Future<void> _handleSave({required bool submitToMeta}) async {
    if (!_formKey.currentState!.validate()) return;

    final rawName = _nameController.text.trim().toLowerCase();
    final displayName = _displayNameController.text.trim();
    final body = _bodyController.text.trim();
    final description = _descriptionController.text.trim();
    final variables = _extractVariables(body);

    setState(() => _isSubmitting = true);

    try {
      final result = await widget.repository.backendClient.createTemplate(
        name: rawName,
        displayName: displayName,
        description: description.isNotEmpty ? description : null,
        category: _category,
        language: _language,
        body: body,
        variables: variables,
        exampleValues: {
          'name': 'Ananya',
          'business_name': widget.repository.settings.businessName.isNotEmpty
              ? widget.repository.settings.businessName
              : 'Our Spa & Wellness',
        },
        submitToMeta: submitToMeta,
      );

      final tplData = result['template'];
      final metaError = result['metaError'];

      WhatsAppTemplate newTemplate;
      if (tplData != null && tplData is Map<String, dynamic>) {
        newTemplate = WhatsAppTemplate.fromJson(tplData);
      } else {
        newTemplate = WhatsAppTemplate(
          id: 'tpl_$rawName',
          name: rawName,
          displayName: displayName,
          description: description.isNotEmpty ? description : null,
          category: _category,
          language: _language,
          status: submitToMeta ? 'pending_approval' : 'draft',
          metaStatus: submitToMeta ? 'PENDING' : 'NOT_SUBMITTED',
          body: body,
          variables: variables,
        );
      }

      await widget.repository.addTemplate(newTemplate);

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      if (metaError != null) {
        // Show informative dialog regarding Meta submission
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AppColors.accentGold),
                SizedBox(width: 8),
                Text('Saved as Local Draft'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('The template "$displayName" was saved locally.'),
                const SizedBox(height: 10),
                const Text(
                  'Meta WhatsApp API Response:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    metaError['message']?.toString() ?? 'Meta token expired or unavailable.',
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'You can submit this template directly via Meta WhatsApp Manager or sync when your access token is renewed.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Understood'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            content: Text(
              submitToMeta
                  ? 'Template submitted for Meta review (status: Pending).'
                  : 'Template saved as Draft.',
            ),
          ),
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: Text('Error saving template: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final variables = _extractVariables(_bodyController.text);
    final bizName = widget.repository.settings.businessName.isNotEmpty
        ? widget.repository.settings.businessName
        : 'Our Spa & Wellness';

    // Live preview resolution
    String resolvedPreview = _bodyController.text;
    resolvedPreview = resolvedPreview.replaceAll('{name}', 'Ananya');
    resolvedPreview = resolvedPreview.replaceAll('{customer_name}', 'Ananya');
    resolvedPreview = resolvedPreview.replaceAll('{client}', 'Ananya');
    resolvedPreview = resolvedPreview.replaceAll('{business_name}', bizName);
    resolvedPreview = resolvedPreview.replaceAll('{spa_name}', bizName);
    resolvedPreview = resolvedPreview.replaceAll('{offer}', '30% OFF');
    resolvedPreview = resolvedPreview.replaceAll('{date}', 'Sunday, 4 PM');

    // Meta numbered preview
    String metaNumberedBody = _bodyController.text;
    for (int i = 0; i < variables.length; i++) {
      metaNumberedBody = metaNumberedBody.replaceAll('{${variables[i]}}', '{{${i + 1}}}');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create WhatsApp Template'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
              // Meta Rules Guidance Banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primarySageContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primarySage.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.verified_outlined, color: AppColors.primarySageDark, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Templates must be approved by Meta before they can be sent in live campaigns. Create a draft or submit for automated review.',
                        style: TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.primarySageDark, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Template Identification
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Template Details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 14),

                    // Display Name
                    TextFormField(
                      controller: _displayNameController,
                      decoration: const InputDecoration(
                        labelText: 'Display Name (e.g. Birthday Pampering)',
                        hintText: 'Festive Radiance Ritual',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Display name is required';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Meta Template Name
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Meta Template Name (snake_case)',
                        hintText: 'festive_radiance_ritual',
                        helperText: 'Lowercase alphanumeric and underscores only (Meta specification)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Meta template name is required';
                        final clean = val.trim().toLowerCase();
                        if (!RegExp(r'^[a-z0-9_]+$').hasMatch(clean)) {
                          return 'Only lowercase letters, numbers, and underscores are allowed';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Category & Language Row
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _category,
                            decoration: const InputDecoration(
                              labelText: 'Category',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'MARKETING', child: Text('Marketing')),
                              DropdownMenuItem(value: 'UTILITY', child: Text('Utility')),
                              DropdownMenuItem(value: 'AUTHENTICATION', child: Text('Authentication')),
                            ],
                            onChanged: (val) => setState(() => _category = val ?? 'MARKETING'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _language,
                            decoration: const InputDecoration(
                              labelText: 'Meta Language Code',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'en_US', child: Text('English (US) [en_US]')),
                              DropdownMenuItem(value: 'en', child: Text('English [en]')),
                              DropdownMenuItem(value: 'en_GB', child: Text('English (UK) [en_GB]')),
                              DropdownMenuItem(value: 'hi', child: Text('Hindi [hi]')),
                              DropdownMenuItem(value: 'te', child: Text('Telugu [te]')),
                              DropdownMenuItem(value: 'ta', child: Text('Tamil [ta]')),
                              DropdownMenuItem(value: 'mr', child: Text('Marathi [mr]')),
                              DropdownMenuItem(value: 'gu', child: Text('Gujarati [gu]')),
                              DropdownMenuItem(value: 'kn', child: Text('Kannada [kn]')),
                              DropdownMenuItem(value: 'bn', child: Text('Bengali [bn]')),
                            ],
                            onChanged: (val) => setState(() => _language = val ?? 'en_US'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Description (optional)
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description (Internal Note)',
                        hintText: 'Send to recurring patrons during festival weeks',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Message Body & Variables
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Message Body & Personalization', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 8),
                    const Text(
                      'Use {variable_name} for recipient personalization. Click chips below to insert.',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 10),

                    // Variable Chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _suggestedVariables.map((v) {
                        return ActionChip(
                          avatar: const Icon(Icons.add_circle_outline_rounded, size: 16, color: AppColors.primarySageDark),
                          label: Text('{$v}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                          backgroundColor: AppColors.primarySageContainer.withValues(alpha: 0.4),
                          onPressed: () => _insertVariable(v),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),

                    // Body Input
                    TextFormField(
                      controller: _bodyController,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: 'Hi {name}! Enjoy our special festive therapy at {business_name}. Book with 30% OFF this week!',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Message body cannot be empty';
                        return null;
                      },
                    ),

                    if (variables.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Text(
                        'Variable Mapping Layer (GlowBlast ↔ Meta)',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.surfaceDark : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          children: variables.asMap().entries.map((entry) {
                            final idx = entry.key + 1;
                            final varName = entry.value;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Text(
                                    '{$varName}',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'monospace', color: AppColors.primarySageDark),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.textMuted),
                                  const SizedBox(width: 8),
                                  Text(
                                    '{{$idx}}',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'monospace', color: AppColors.whatsApp),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '(Meta Parameter $idx)',
                                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Live Preview Card
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.chat_bubble_outline_rounded, color: AppColors.whatsApp, size: 18),
                        SizedBox(width: 8),
                        Text('Customer Preview (WhatsApp)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E2D24) : AppColors.whatsAppBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.whatsApp.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        resolvedPreview.isNotEmpty
                            ? resolvedPreview
                            : 'Type a message above to see preview here...',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Action Buttons
              if (_isSubmitting)
                const Center(child: CircularProgressIndicator())
              else ...[
                PrimaryButton(
                  text: 'Submit to Meta for Approval',
                  icon: Icons.cloud_upload_rounded,
                  onPressed: () => _handleSave(submitToMeta: true),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _handleSave(submitToMeta: false),
                  icon: const Icon(Icons.bookmark_border_rounded, size: 18),
                  label: const Text('Save as Local Draft', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.primarySage),
                    foregroundColor: AppColors.primarySageDark,
                  ),
                ),
              ],
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
