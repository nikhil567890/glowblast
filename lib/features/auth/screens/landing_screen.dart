import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../data/repositories/app_repository.dart';
import '../../../services/excel_service.dart';
import '../../main_nav/main_navigation_screen.dart';

class LandingScreen extends StatefulWidget {
  final AppRepository repository;

  const LandingScreen({super.key, required this.repository});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _businessNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _businessNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final fullName = _fullNameController.text.trim();
    final businessName = _businessNameController.text.trim();
    final rawPhone = _phoneController.text.trim();
    final cleanPhone = ExcelService.formatIndianPhone(rawPhone);

    final updated = widget.repository.settings.copyWith(
      fullName: fullName,
      businessName: businessName,
      phone: cleanPhone,
    );

    await widget.repository.updateSettings(updated);

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, anim, secAnim) => MainNavigationScreen(repository: widget.repository),
        transitionsBuilder: (context, anim, secAnim, child) => FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.warmCream,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Brand Icon / Header
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primarySage, AppColors.primarySageDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primarySageDark.withValues(alpha: 0.25),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.spa_rounded, size: 44, color: Colors.white),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Title
                  Text(
                    'Welcome to ${AppStrings.appName}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Set up your business profile to personalize WhatsApp campaigns and client engagement.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Form Container
                  Container(
                    padding: const EdgeInsets.all(22),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Field 1: Full Name
                        const Text(
                          'Full Name',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _fullNameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            hintText: 'e.g. Pooja Sharma',
                            prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                            filled: true,
                            fillColor: isDark ? AppColors.surfaceDark : AppColors.warmCream,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your full name';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 18),

                        // Field 2: Business Name
                        const Text(
                          'Business Name',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _businessNameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            hintText: 'e.g. Aura Luxury Spa & Wellness',
                            prefixIcon: const Icon(Icons.storefront_outlined, size: 20),
                            filled: true,
                            fillColor: isDark ? AppColors.surfaceDark : AppColors.warmCream,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your business name';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 18),

                        // Field 3: Phone Number
                        const Text(
                          'Phone Number',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            hintText: '98765 43210',
                            prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                            prefixText: '+91 ',
                            prefixStyle: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                            ),
                            filled: true,
                            fillColor: isDark ? AppColors.surfaceDark : AppColors.warmCream,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your 10-digit mobile number';
                            }
                            final digits = ExcelService.extractClean10Digits(value);
                            if (digits.length != 10) {
                              return 'Mobile number must be exactly 10 digits';
                            }
                            if (!RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
                              return 'Please enter a valid mobile number starting with 6, 7, 8, or 9';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 28),

                        PrimaryButton(
                          text: 'Get Started',
                          icon: Icons.arrow_forward_rounded,
                          isLoading: _isLoading,
                          onPressed: _submit,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.accentGold),
                      const SizedBox(width: 6),
                      Text(
                        'Saved locally on your device',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
