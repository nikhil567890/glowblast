import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/widgets/app_card.dart';
import '../../../data/repositories/app_repository.dart';
import '../../../services/excel_service.dart';
import '../../../services/glowblast_backend_client.dart';
import '../../auth/screens/landing_screen.dart';
import 'opt_out_screen.dart';
import 'recharge_meta_balance_screen.dart';
import 'whatsapp_connection_screen.dart';
import 'team_management_screen.dart';

class SettingsScreen extends StatefulWidget {
  final AppRepository repository;

  const SettingsScreen({super.key, required this.repository});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isCheckingBackend = false;
  bool? _isBackendOnline;
  BackendHealthStatus? _lastHealthStatus;
  bool _showDiagnostics = false;
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    _checkBackendStatus();
  }

  Future<void> _checkBackendStatus() async {
    setState(() => _isCheckingBackend = true);
    final status = await widget.repository.backendClient.healthCheck();
    if (mounted) {
      setState(() {
        _isCheckingBackend = false;
        _isBackendOnline = status.isOnline;
        _lastHealthStatus = status;
      });
    }
  }

  void _editBackendUrl() {
    final currentUrl = widget.repository.settings.backendUrl;
    final urlCtrl = TextEditingController(text: currentUrl);
    String? errorText;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Backend Server URL'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Specify your GlowBlast backend base URL. The default cloud production server is:',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primarySageContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const SelectableText(
                  ApiConstants.defaultProductionBackendUrl,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primarySage),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: urlCtrl,
                decoration: InputDecoration(
                  labelText: 'Backend URL',
                  hintText: ApiConstants.defaultProductionBackendUrl,
                  prefixIcon: const Icon(Icons.dns_rounded),
                  errorText: errorText,
                ),
                onChanged: (_) {
                  if (errorText != null) {
                    setDialogState(() => errorText = null);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                urlCtrl.text = ApiConstants.defaultProductionBackendUrl;
                setDialogState(() => errorText = null);
              },
              child: const Text('Reset Default'),
            ),
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primarySage,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                var newUrl = urlCtrl.text.trim();
                if (newUrl.isEmpty) {
                  newUrl = ApiConstants.defaultProductionBackendUrl;
                }
                if (kReleaseMode && !newUrl.startsWith('https://')) {
                  setDialogState(() {
                    errorText = 'Release builds require a secure HTTPS URL (https://...)';
                  });
                  return;
                }
                Navigator.pop(dialogCtx);
                final normalized = ApiConstants.normalizeBackendUrl(newUrl);
                final updated = widget.repository.settings.copyWith(backendUrl: normalized);
                await widget.repository.updateSettings(updated);
                if (mounted) {
                  _checkBackendStatus();
                }
              },
              child: const Text('Save & Reconnect'),
            ),
          ],
        ),
      ),
    );
  }
  void _editBusinessProfile() {
    final settings = widget.repository.settings;
    final fullNameCtrl = TextEditingController(text: settings.fullName);
    final businessNameCtrl = TextEditingController(text: settings.businessName);
    final phoneCtrl = TextEditingController(
      text: settings.phone.startsWith('+91 ')
          ? settings.phone.substring(4)
          : settings.phone,
    );
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Business Profile'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your profile details are used across messages, campaign previews and reports.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: fullNameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Full Name is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: businessNameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Business Name',
                    prefixIcon: Icon(Icons.storefront_outlined, size: 20),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Business Name is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    prefixText: '+91 ',
                    prefixIcon: Icon(Icons.phone_outlined, size: 20),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Phone Number is required';
                    final digits = ExcelService.extractClean10Digits(v);
                    if (digits.length != 10) return 'Must be 10 digits';
                    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
                      return 'Must start with 6, 7, 8, or 9';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primarySage,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final cleanPhone = ExcelService.formatIndianPhone(phoneCtrl.text.trim());
              final updated = settings.copyWith(
                fullName: fullNameCtrl.text.trim(),
                businessName: businessNameCtrl.text.trim(),
                phone: cleanPhone,
              );
              await widget.repository.updateSettings(updated);

              // Also sync with backend business profile if active business exists
              if (widget.repository.hasActiveBusiness) {
                await widget.repository.updateBusinessProfile(
                  displayName: businessNameCtrl.text.trim(),
                  phone: cleanPhone,
                );
              }

              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✓ Business profile updated across the app.')),
              );
            },
            child: const Text('Save Profile'),
          ),
        ],
      ),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Log out of GlowBlast?'),
        content: const Text(
          'Are you sure you want to log out? You will need to sign in again to access the application. Your campaign history and customer database will remain safely stored on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
            ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: _isLoggingOut
                ? null
                : () async {
                    setState(() => _isLoggingOut = true);
                    Navigator.pop(dialogCtx);
                    try {
                      // 1. Call backend logout once
                      await widget.repository.backendClient.logout(
                        token: widget.repository.authToken,
                      );
                      // 2. Clear local auth session securely
                      await widget.repository.clearAuthSession();
                      // 3. Navigate to Landing Page/Login
                      if (!mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (context) => LandingScreen(repository: widget.repository),
                        ),
                        (route) => false,
                      );
                    } finally {
                      if (mounted) setState(() => _isLoggingOut = false);
                    }
                  },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.repository,
      builder: (listenCtx, _) {
        final settings = widget.repository.settings;
        final isDark = Theme.of(listenCtx).brightness == Brightness.dark;

        final displayName = settings.fullName.isNotEmpty ? settings.fullName : 'Business Owner';
        final displayBusiness = settings.businessName.isNotEmpty ? settings.businessName : 'Spa & Wellness';
        final displayPhone = settings.phone.isNotEmpty ? settings.phone : '+91 Not Set';

        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings'),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    children: [
                      // Section 0: Business Switcher (if user belongs to businesses)
                      if (widget.repository.userBusinesses.isNotEmpty) ...[
                        AppCard(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.primarySageContainer,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.swap_horiz_rounded, color: AppColors.primarySageDark, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Active Business Workspace', style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                                    DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        isExpanded: true,
                                        value: widget.repository.activeBusinessId,
                                        items: widget.repository.userBusinesses.map((b) {
                                          return DropdownMenuItem<String>(
                                            value: b.businessId,
                                            child: Text(
                                              '${b.displayName} (${b.role.toUpperCase()})',
                                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (newId) async {
                                          if (newId != null && newId != widget.repository.activeBusinessId) {
                                            final messenger = ScaffoldMessenger.of(context);
                                            final target = widget.repository.userBusinesses.firstWhere((b) => b.businessId == newId);
                                            await widget.repository.switchActiveBusiness(target);
                                            messenger.showSnackBar(
                                              SnackBar(
                                                content: Text('Switched to ${target.displayName}'),
                                                duration: const Duration(seconds: 2),
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Section 1: Business Profile Card
                      AppCard(
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
                                        color: AppColors.primarySageContainer,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.storefront_rounded, color: AppColors.primarySageDark, size: 20),
                                    ),
                                    const SizedBox(width: 10),
                                    const Text('Business Profile', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                  ],
                                ),
                                if (widget.repository.isBusinessStaff)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isDark ? AppColors.surfaceDark : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text('Staff (Read-Only)', style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                                  )
                                else
                                  TextButton.icon(
                                    onPressed: _editBusinessProfile,
                                    icon: const Icon(Icons.edit_outlined, size: 16),
                                    label: const Text('Edit Profile'),
                                  ),
                              ],
                            ),
                            const Divider(height: 20),
                            _buildInfoRow('Full Name', displayName, isDark),
                            const SizedBox(height: 10),
                            _buildInfoRow(
                              'Business Name',
                              widget.repository.activeBusiness?.displayName ?? displayBusiness,
                              isDark,
                            ),
                            if (widget.repository.activeBusiness != null) ...[
                              const SizedBox(height: 10),
                              _buildInfoRow(
                                'Assigned Role',
                                widget.repository.activeBusiness!.role.toUpperCase(),
                                isDark,
                              ),
                            ],
                            const SizedBox(height: 10),
                            _buildInfoRow('Contact Phone', displayPhone, isDark),
                            if (widget.repository.currentUser?.email != null) ...[
                              const SizedBox(height: 10),
                              _buildInfoRow('Account Email', widget.repository.currentUser!.email, isDark),
                            ],
                            const Divider(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.shield_outlined, size: 14, color: AppColors.success),
                                    const SizedBox(width: 6),
                                    Text(
                                      widget.repository.isAuthenticated
                                          ? 'Verified Account Session'
                                          : 'Local Guest Mode',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.error,
                                    side: const BorderSide(color: AppColors.error, width: 1.2),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  icon: const Icon(Icons.logout_rounded, size: 16),
                                  label: const Text(
                                    'Log Out',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                  ),
                                  onPressed: _confirmLogout,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Section 1.5: Team Management Card
                      if (widget.repository.hasActiveBusiness) ...[
                        AppCard(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.people_alt_rounded, color: Color(0xFF2563EB), size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Team & Members', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                                      const SizedBox(height: 2),
                                      Text(
                                        widget.repository.isBusinessStaff
                                            ? 'View team roster'
                                            : 'Invite members & manage permissions',
                                        style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                                label: Text(
                                  widget.repository.isBusinessStaff ? 'View Team' : 'Manage Team',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                ),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => TeamManagementScreen(repository: widget.repository),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Section 2: Messaging Mode & WhatsApp Configuration
                      AppCard(
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
                                        color: AppColors.whatsAppBg,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.chat_rounded, color: AppColors.whatsApp, size: 20),
                                    ),
                                    const SizedBox(width: 10),
                                    const Text('WhatsApp Business', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _isBackendOnline == true ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _isBackendOnline == true ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                                        size: 12,
                                        color: _isBackendOnline == true ? AppColors.success : AppColors.error,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _isCheckingBackend
                                            ? 'Checking...'
                                            : (_isBackendOnline == true ? 'Connected' : 'Offline'),
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: _isBackendOnline == true ? AppColors.success : AppColors.error,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.surfaceDark : const Color(0xFFF9FAF9),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.borderLight),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.verified_user_rounded, size: 16, color: AppColors.success),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _isCheckingBackend
                                              ? 'Connecting to secure server...'
                                              : (_isBackendOnline == true
                                                  ? 'Meta Cloud API • Spa Connection Active'
                                                  : 'Server Unreachable • Please check network'),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: _isBackendOnline == true ? AppColors.success : AppColors.error,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: _isCheckingBackend
                                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                            : const Icon(Icons.refresh_rounded, size: 18),
                                        onPressed: _checkBackendStatus,
                                        tooltip: 'Ping Server Health',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Official WhatsApp Business Account connection for promotional broadcasts and transactional messages.\n'
                                    '• Requires explicit customer consent before sending.\n'
                                    '• Unsubscribes and opt-outs are enforced automatically.',
                                    style: TextStyle(fontSize: 11.5, height: 1.4, color: AppColors.textMuted),
                                  ),
                                  const SizedBox(height: 10),
                                  // Collapsible Administrator Diagnostics
                                  InkWell(
                                    onTap: () => setState(() => _showDiagnostics = !_showDiagnostics),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _showDiagnostics ? 'Hide Administrator Diagnostics ▲' : 'Administrator Diagnostics ▼',
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primarySage),
                                          ),
                                          Text(
                                            _lastHealthStatus != null
                                                ? '${_lastHealthStatus!.statusCode ?? "ERR"} · ${_lastHealthStatus!.latency?.inMilliseconds ?? 0}ms'
                                                : 'Tap to check',
                                            style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (_showDiagnostics) ...[
                                    Container(
                                      margin: const EdgeInsets.only(top: 8),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isDark ? AppColors.cardDark : Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: AppColors.borderLight),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Connection: ${_isBackendOnline == true ? "🟢 Online" : "🔴 Offline"}', style: const TextStyle(fontSize: 11)),
                                          Text('Status: ${_lastHealthStatus?.statusCode != null ? "${_lastHealthStatus!.statusCode} OK" : "N/A"}', style: const TextStyle(fontSize: 11)),
                                          Text('Latency: ${_lastHealthStatus?.latency != null ? "${_lastHealthStatus!.latency!.inMilliseconds} ms" : "N/A"}', style: const TextStyle(fontSize: 11)),
                                          if (_lastHealthStatus?.error != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 2),
                                              child: Text('Error: ${_lastHealthStatus!.error}', style: const TextStyle(fontSize: 11, color: AppColors.error)),
                                            ),
                                          const SizedBox(height: 6),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              TextButton.icon(
                                                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                                icon: const Icon(Icons.settings_ethernet_rounded, size: 14),
                                                label: const Text('Configure Server URL', style: TextStyle(fontSize: 11)),
                                                onPressed: _editBackendUrl,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const Divider(height: 24),

                            // Business WABA Account Connection Row
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.surfaceDark : const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFBBF7D0)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.hub_outlined, size: 16, color: AppColors.whatsApp),
                                            const SizedBox(width: 6),
                                            Text(
                                              widget.repository.activeBusiness != null
                                                  ? '${widget.repository.activeBusiness!.displayName} WABA'
                                                  : 'WhatsApp Business Account',
                                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        const Text(
                                          'Dedicated Meta phone number & credentials',
                                          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (widget.repository.isBusinessStaff)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isDark ? AppColors.surfaceDark : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFFCBD5E1)),
                                      ),
                                      child: const Text(
                                        'Admin Managed',
                                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                                      ),
                                    )
                                  else
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.whatsApp,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      icon: const Icon(Icons.settings_rounded, size: 14),
                                      label: const Text('Manage WABA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) => WhatsAppConnectionScreen(repository: widget.repository),
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Meta messaging balance & recharge row
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.surfaceDark : AppColors.warmCream,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Meta Messaging Balance',
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Managed via Meta Business Suite',
                                          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primarySage,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: const Icon(Icons.open_in_new_rounded, size: 15),
                                    label: const Text('Recharge Balance', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => RechargeMetaBalanceScreen(repository: widget.repository),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Section 3: Opt-Out Management
                      AppCard(
                        padding: const EdgeInsets.all(16),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.surfaceDark : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.do_not_disturb_on_outlined, color: AppColors.error, size: 22),
                          ),
                          title: const Text('Opt-Out Management', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          subtitle: Text(
                            '${widget.repository.optedOutCustomersCount} opted-out contacts excluded from blasts',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => OptOutScreen(repository: widget.repository),
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Section 4: App Theme
                      AppCard(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Display Appearance', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            const SizedBox(height: 12),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'system', label: Text('System'), icon: Icon(Icons.brightness_auto)),
                                ButtonSegment(value: 'light', label: Text('Light'), icon: Icon(Icons.light_mode)),
                                ButtonSegment(value: 'dark', label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                              ],
                              selected: {settings.themeMode},
                              onSelectionChanged: (set) async {
                                final updated = settings.copyWith(themeMode: set.first);
                                await widget.repository.updateSettings(updated);
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.textLight : AppColors.textCharcoal,
          ),
        ),
      ],
    );
  }
}
