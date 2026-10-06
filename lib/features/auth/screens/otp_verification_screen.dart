import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../data/models/auth_user.dart';
import '../../../data/repositories/app_repository.dart';
import '../../main_nav/main_navigation_screen.dart';

class OtpVerificationScreen extends StatefulWidget {
  final AppRepository repository;
  final String email;
  final String name;
  final String? businessName;
  final String? phone;

  const OtpVerificationScreen({
    super.key,
    required this.repository,
    required this.email,
    required this.name,
    this.businessName,
    this.phone,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final TextEditingController _otpController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;

  // 60-second resend cooldown timer
  int _resendCooldownSeconds = 60;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _startCooldownTimer();
  }

  void _startCooldownTimer() {
    setState(() => _resendCooldownSeconds = 60);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldownSeconds > 0) {
        setState(() => _resendCooldownSeconds--);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handleVerify() async {
    final rawOtp = _otpController.text.trim();
    if (rawOtp.length != 6 || !RegExp(r'^\d{6}$').hasMatch(rawOtp)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the 6-digit verification code.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final result = await widget.repository.backendClient.verifyRegisterOtp(
      email: widget.email,
      otp: rawOtp,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      final token = result['token'] as String? ?? '';
      final userData = result['user'] as Map<String, dynamic>? ?? {};
      final authUser = AuthUser.fromJson(userData);

      // Save authenticated session securely in repository
      await widget.repository.saveAuthSession(token, authUser);

      // Personalize business profile with user credentials
      final updatedSettings = widget.repository.settings.copyWith(
        fullName: widget.name.isNotEmpty ? widget.name : widget.repository.settings.fullName,
        businessName: (widget.businessName != null && widget.businessName!.isNotEmpty)
            ? widget.businessName!
            : (authUser.businessName ?? widget.repository.settings.businessName),
        phone: (widget.phone != null && widget.phone!.isNotEmpty)
            ? widget.phone!
            : (authUser.phone ?? widget.repository.settings.phone),
      );
      await widget.repository.updateSettings(updatedSettings);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Account verified successfully! Welcome to GlowBlast.'),
          backgroundColor: AppColors.primarySageDark,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Navigate directly to Home
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (context, anim, secAnim) => MainNavigationScreen(
            repository: widget.repository,
          ),
          transitionsBuilder: (context, anim, secAnim, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
        (route) => false,
      );
    } else {
      final errorMap = result['error'] as Map<String, dynamic>?;
      final errorMsg = errorMap?['message'] as String? ?? 'Invalid verification code.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(errorMsg)),
            ],
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleResend() async {
    if (_resendCooldownSeconds > 0) return;

    setState(() => _isResending = true);

    // Request new OTP via backend Brevo service
    final result = await widget.repository.backendClient.requestRegisterOtp(
      name: widget.name,
      email: widget.email,
      password: 'TemporaryResend123!', // Kept same on backend or refreshed
    );

    if (!mounted) return;
    setState(() => _isResending = false);

    if (result['success'] == true) {
      _startCooldownTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('New verification code sent to ${widget.email}.'),
          backgroundColor: AppColors.primarySageDark,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final errorMap = result['error'] as Map<String, dynamic>?;
      final errorMsg = errorMap?['message'] as String? ?? 'Unable to resend verification code.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.warmCream,
      appBar: AppBar(
        title: const Text('Verify Email'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Icon
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.accentGoldLight, AppColors.accentGold],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accentGold.withValues(alpha: 0.3),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.mark_email_read_rounded, size: 38, color: Colors.white),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Text(
                  'Verify Your Email',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                  ),
                ),

                const SizedBox(height: 8),

                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 13.5,
                      color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                      height: 1.45,
                    ),
                    children: [
                      const TextSpan(text: 'We sent a 6-digit code to\n'),
                      TextSpan(
                        text: widget.email,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Card Container
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.cardDark : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                    border: Border.all(
                      color: isDark ? AppColors.borderDark : AppColors.borderLight,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Enter 6-Digit Code',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                      const SizedBox(height: 16),

                      // Code Input Field
                      TextField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 12,
                          fontFamily: 'monospace',
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: '000000',
                          hintStyle: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 12,
                            color: isDark ? Colors.white24 : Colors.black12,
                          ),
                          filled: true,
                          fillColor: isDark ? AppColors.surfaceDark : AppColors.warmCream,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: isDark ? AppColors.borderDark : AppColors.borderLight,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: AppColors.primarySage, width: 2),
                          ),
                        ),
                        onSubmitted: (_) => _handleVerify(),
                      ),

                      const SizedBox(height: 14),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.timer_outlined, size: 14, color: AppColors.accentGold),
                          const SizedBox(width: 5),
                          Text(
                            'Code expires in 10 minutes',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      PrimaryButton(
                        text: 'Verify & Activate',
                        icon: Icons.check_circle_outline_rounded,
                        isLoading: _isLoading,
                        onPressed: _handleVerify,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Resend section
                Center(
                  child: _resendCooldownSeconds > 0
                      ? Text(
                          'Resend code in $_resendCooldownSeconds seconds',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                          ),
                        )
                      : TextButton.icon(
                          onPressed: _isResending ? null : _handleResend,
                          icon: _isResending
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.replay_rounded, size: 16),
                          label: const Text(
                            'Resend Code',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
