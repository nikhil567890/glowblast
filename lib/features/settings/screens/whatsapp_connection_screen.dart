import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../data/repositories/app_repository.dart';
import '../../../services/glowblast_backend_client.dart';

class WhatsAppConnectionScreen extends StatefulWidget {
  final AppRepository repository;

  const WhatsAppConnectionScreen({super.key, required this.repository});

  @override
  State<WhatsAppConnectionScreen> createState() => _WhatsAppConnectionScreenState();
}

class _WhatsAppConnectionScreenState extends State<WhatsAppConnectionScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _successMessage;

  BusinessWabaConnection? _connection;
  String _selectedMode = 'test';

  // Form controllers
  final _wabaIdController = TextEditingController();
  final _phoneNumberIdController = TextEditingController();
  final _displayNumberController = TextEditingController();
  final _accessTokenController = TextEditingController();
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    _loadConnection();
  }

  @override
  void dispose() {
    _wabaIdController.dispose();
    _phoneNumberIdController.dispose();
    _displayNumberController.dispose();
    _accessTokenController.dispose();
    super.dispose();
  }

  Future<void> _loadConnection() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final conn = await widget.repository.backendClient.getBusinessWabaConnection(
        mode: _selectedMode,
      );
      if (mounted) {
        setState(() {
          _connection = conn;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load WhatsApp connection: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleConnect() async {
    final wabaId = _wabaIdController.text.trim();
    final phoneNumberId = _phoneNumberIdController.text.trim();
    final token = _accessTokenController.text.trim();
    final displayNumber = _displayNumberController.text.trim();

    if (wabaId.isEmpty || phoneNumberId.isEmpty || token.isEmpty) {
      setState(() {
        _errorMessage = 'Please provide WABA ID, Phone Number ID, and System User Access Token.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final result = await widget.repository.backendClient.connectBusinessWaba(
        wabaId: wabaId,
        phoneNumberId: phoneNumberId,
        accessToken: token,
        displayNumber: displayNumber.isNotEmpty ? displayNumber : null,
        mode: _selectedMode,
      );

      if (result['success'] == true) {
        _accessTokenController.clear();
        setState(() {
          _successMessage = 'WhatsApp Business Account connected securely!';
          _isSaving = false;
        });
        await _loadConnection();
      } else {
        final err = result['error']?['message'] ?? 'Connection failed. Please check credentials.';
        setState(() {
          _errorMessage = err;
          _isSaving = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error: $e';
        _isSaving = false;
      });
    }
  }

  Future<void> _handleDisconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect WhatsApp?'),
        content: const Text(
          'Messages will no longer be sent or received for this business until a new connection is configured. Stored encryption tokens will be deactivated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Disconnect', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);
    final success = await widget.repository.backendClient.disconnectBusinessWaba(
      mode: _selectedMode,
    );

    if (mounted) {
      setState(() {
        _isSaving = false;
        if (success) {
          _connection = null;
          _successMessage = 'WhatsApp account disconnected.';
        } else {
          _errorMessage = 'Failed to disconnect. Please retry.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeBiz = widget.repository.activeBusiness;
    final isOwnerOrAdmin = activeBiz?.isAdmin ?? true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('WhatsApp Connection'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadConnection,
            tooltip: 'Refresh Connection Status',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          children: [
            // Business Context Card
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primarySageContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.storefront_rounded, color: AppColors.primarySageDark, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activeBiz?.displayName ?? 'Flagship Spa',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Business ID: ${activeBiz?.businessId ?? "Initial Spa"}',
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceDark : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      activeBiz?.role.toUpperCase() ?? 'ADMIN',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Mode Selector
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'test',
                  label: Text('Test Sandbox'),
                  icon: Icon(Icons.science_outlined, size: 16),
                ),
                ButtonSegment(
                  value: 'production',
                  label: Text('Production WABA'),
                  icon: Icon(Icons.verified_rounded, size: 16),
                ),
              ],
              selected: {_selectedMode},
              onSelectionChanged: (newVal) {
                setState(() {
                  _selectedMode = newVal.first;
                });
                _loadConnection();
              },
            ),

            const SizedBox(height: 16),

            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.error),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.error, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),

            if (_successMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.success),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _successMessage!,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.success, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_connection != null && _connection!.isActive)
              _buildConnectedCard(isDark)
            else
              _buildNotConnectedView(isDark, isOwnerOrAdmin),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedCard(bool isDark) {
    final conn = _connection!;
    final isInitialLegacy = conn.source == 'initial_spa_legacy_fallback';

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'WhatsApp Connected',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      Text(
                        isInitialLegacy
                            ? 'Flagship Spa Verified Credentials'
                            : 'Business-Dedicated Connection',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'ACTIVE',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.success),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          _buildDetailRow('Display Phone Number', conn.displayNumber ?? 'N/A'),
          const SizedBox(height: 8),
          _buildDetailRow('Meta Phone Number ID', conn.phoneNumberId),
          const SizedBox(height: 8),
          _buildDetailRow('WhatsApp Business Account (WABA) ID', conn.wabaId),
          if (conn.verifiedName != null) ...[
            const SizedBox(height: 8),
            _buildDetailRow('Verified Business Name', conn.verifiedName!),
          ],
          const SizedBox(height: 16),
          // Security Callout
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.primarySage),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tokens are encrypted via AES-256-GCM with tenant-bound authentication. Access tokens are never returned or stored in client storage.',
                    style: TextStyle(fontSize: 11, height: 1.35, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                ),
                icon: const Icon(Icons.link_off_rounded, size: 16),
                label: const Text('Disconnect Connection'),
                onPressed: _isSaving ? null : _handleDisconnect,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotConnectedView(bool isDark, bool canManage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status Alert Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFD54F)),
          ),
          child: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFF57F17), size: 24),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No WhatsApp Account Connected',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFFE65100)),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Messages cannot be dispatched from this business until you connect your verified WhatsApp Business Account.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF795548)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Setup Guide Card
        AppCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Meta WhatsApp Onboarding Guide',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 8),
              const Text(
                'Connect your official WhatsApp Business Account using Meta Cloud API. Each business in GlowBlast uses its own isolated credentials.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const Divider(height: 20),
              _buildStepRow(
                '1',
                'Create a Meta App',
                'Go to developers.facebook.com and create a Business app with WhatsApp product enabled.',
              ),
              const SizedBox(height: 12),
              _buildStepRow(
                '2',
                'Configure Webhook in Meta Dashboard',
                'In Meta App Settings > WhatsApp > Configuration, subscribe to "messages" with the webhook URL below:',
              ),
              const SizedBox(height: 8),
              _buildCopyField('Callback URL', 'https://glowblast-api.onrender.com/api/webhook/whatsapp'),
              const SizedBox(height: 6),
              _buildCopyField('Verify Token', 'glowblast_webhook_verify_token'),
              const SizedBox(height: 12),
              _buildStepRow(
                '3',
                'Generate System User Access Token',
                'In Meta Business Settings > System Users, generate a permanent token with "whatsapp_business_messaging" and "whatsapp_business_management" permissions.',
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Connection Form (Admin/Owner only)
        if (canManage)
          AppCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Connect WhatsApp Account',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Credentials will be encrypted with AES-256-GCM and stored securely on the backend.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _wabaIdController,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp Business Account ID (WABA ID) *',
                    hintText: 'e.g. 1633948435034571',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneNumberIdController,
                  decoration: const InputDecoration(
                    labelText: 'Meta Phone Number ID *',
                    hintText: 'e.g. 1272717865934207',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _displayNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Display Phone Number (Optional)',
                    hintText: 'e.g. +1 (555) 632-5494',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _accessTokenController,
                  obscureText: _obscureToken,
                  decoration: InputDecoration(
                    labelText: 'System User Permanent Access Token *',
                    hintText: 'EAAB...',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureToken ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscureToken = !_obscureToken),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.whatsApp,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.lock_rounded, size: 18),
                    label: Text(_isSaving ? 'Encrypting & Connecting...' : 'Verify & Connect WhatsApp'),
                    onPressed: _isSaving ? null : _handleConnect,
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: AppColors.textMuted),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Administrator permissions are required to configure WhatsApp credentials for this business.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildStepRow(String number, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 11,
          backgroundColor: AppColors.primarySage,
          child: Text(number, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(description, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.3)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCopyField(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 16),
            tooltip: 'Copy $label',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$label copied to clipboard')),
              );
            },
          ),
        ],
      ),
    );
  }
}
