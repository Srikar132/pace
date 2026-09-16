import 'package:flutter/material.dart';
import 'package:pace/core/constants/images.dart';
import 'package:pace/models/auth_actions_bottom_model.dart';
import 'package:pace/models/model_manager.dart';
import 'package:pace/widgets/testimonial_card.dart';

class EntryScreen extends StatelessWidget {
  const EntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(kEntryBackgroundImage, fit: BoxFit.cover),
          ),

          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.25)),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(
                left: 24.0,
                right: 24.0,
                top: 70.0,
                bottom: 24.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(width: 16),
                      Text(
                        'Pace',
                        style: theme.textTheme.displayLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),

                  const SizedBox(height: 100),

                  Text(
                    '#1',
                    style: theme.textTheme.displayLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'Study App',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      fontSize: 30,
                      color: theme.colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'for students to',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      fontSize: 30,
                      color: theme.colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'focus',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      fontSize: 30,
                      color: theme.colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const Spacer(),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TrustItem(
                        title: "Trusted by",
                        value: "2M+",
                        subtitle: "students",
                        theme: theme,
                      ),
                      const SizedBox(width: 32),
                      TrustItem(
                        title: "Rated",
                        value: "4.7",
                        subtitle: "stars",
                        theme: theme,
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),

                  ElevatedButton(
                    onPressed: () {
                      BottomSheetManager.show(
                        context: context,
                        child: const AuthActionsBottomModel(),
                        isDismissible: false,
                        enableDrag: true,
                      );
                    },
                    child: const Text('Get Started'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
