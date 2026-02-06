import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/constants/app_colors.dart';

class StoryStepLayout extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? bottomAction;
  final bool showProgress;
  final int currentStep;
  final int totalSteps;
  final VoidCallback? onBack;

  const StoryStepLayout({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.bottomAction,
    this.showProgress = true,
    this.currentStep = 1,
    this.totalSteps = 4,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Progress Bar (Story Style)
            if (showProgress)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
                child: Row(
                  children: List.generate(totalSteps, (index) {
                    final isActive = index < currentStep;
                    return Expanded(
                      child: Container(
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: isActive ? AppColors.primary : Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
              ),

            // Header (Back button + Title)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Stack(
                alignment: Alignment.center,
                children: [
                   if (onBack != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                        onPressed: onBack,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  Column(
                    children: [
                      Text(
                        'Etapa $currentStep de $totalSteps',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Main Content Area
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        subtitle!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: 18,
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    body,
                  ],
                ),
              ),
            ),

            // Bottom Action Area
            if (bottomAction != null)
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: bottomAction,
              ),
          ],
        ),
      ),
    );
  }
}
