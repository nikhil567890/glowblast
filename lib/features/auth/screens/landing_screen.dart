import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../data/repositories/app_repository.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class LandingScreen extends StatelessWidget {
  final AppRepository repository;

  const LandingScreen({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.warmCream,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),

                      // GlowBlast Brand Icon
                      Center(
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primarySage, AppColors.primarySageDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: AppColors.accentGold.withValues(alpha: 0.5),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primarySageDark.withValues(alpha: 0.3),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(Icons.spa_rounded, size: 48, color: Colors.white),
                          ),
                        ),
                      ),

                      const SizedBox(height: 22),

                      // Title
                      Text(
                        AppStrings.appName,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                        ),
                      ),

                      const SizedBox(height: 6),

                      Text(
                        'WHATSAPP MARKETING FOR SPAS & SALONS',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.0,
                          color: AppColors.accentGold,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Product Description
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'Automate high-converting WhatsApp promotional campaigns, engage clientele, and track real-time delivery with official Meta Cloud API.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                            height: 1.45,
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Value Highlights Card
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.cardDark : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isDark ? AppColors.borderDark : AppColors.borderLight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            _buildFeatureRow(
                              Icons.verified_rounded,
                              AppColors.whatsApp,
                              'Official Meta Cloud API v22.0',
                              'Verified messaging gateway without risk of ban.',
                              isDark,
                            ),
                            const Divider(height: 20),
                            _buildFeatureRow(
                              Icons.mark_email_read_outlined,
                              AppColors.primarySage,
                              'Secure Brevo OTP Verification',
                              'Instant 6-digit transactional email protection.',
                              isDark,
                            ),
                            const Divider(height: 20),
                            _buildFeatureRow(
                              Icons.insights_rounded,
                              AppColors.accentGold,
                              '6-Month Campaign Analytics',
                              'Dynamic tracking for delivered, read, and replies.',
                              isDark,
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),
                      const SizedBox(height: 32),

                      // Main CTA: "Get Started" -> RegisterScreen
                      PrimaryButton(
                        text: 'Get Started',
                        icon: Icons.arrow_forward_rounded,
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => RegisterScreen(repository: repository),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 12),

                      // Secondary CTA: "Sign In" -> LoginScreen
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? AppColors.textLight : AppColors.textCharcoal,
                          side: BorderSide(
                            color: isDark ? AppColors.borderDark : AppColors.borderLight,
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.login_rounded, size: 18),
                        label: const Text(
                          'Sign In',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => LoginScreen(repository: repository),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      // Create Account Link
                      Center(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => RegisterScreen(repository: repository),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                                ),
                                children: const [
                                  TextSpan(text: 'New salon or spa business? '),
                                  TextSpan(
                                    text: 'Create Account',
                                    style: TextStyle(
                                      color: AppColors.primarySage,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFeatureRow(
    IconData icon,
    Color iconColor,
    String title,
    String desc,
    bool isDark,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 18),
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
                  fontSize: 13,
                  color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
