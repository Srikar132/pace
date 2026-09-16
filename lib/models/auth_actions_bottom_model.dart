import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/core/constants/images.dart';
import 'package:pace/presentation/providers/auth_provider.dart';
import 'package:pace/widgets/bottom_sheet_darg_handler.dart';

class AuthActionsBottomModel extends ConsumerWidget {
  const AuthActionsBottomModel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final authState = ref.watch(authNotifierProvider);
    final authNotifier = ref.read(authNotifierProvider.notifier);

    return Padding(
      padding: const EdgeInsets.only(left: 24.0, right: 24.0, bottom: 24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BottomSheetDragHandle(),

          const SizedBox(height: 20.0),

          Text(
            'Welcome to Pace!',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 20.0),
          // Google Sign In Button
          authState.isSigningIn
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                )
              : ElevatedButton(
                  onPressed: () async {
                    await authNotifier.signInWithGoogle();
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        kGoogleLogoImage,
                        height: 20.0,
                      ),
                      const SizedBox(width: 8.0),
                      const Text('Continue with Google'),
                    ],
                  ),
                ),

          const SizedBox(height: 8.0),

          const Divider(),

          OutlinedButton(
            onPressed: () {
              Navigator.of(context).pop('signup');
            },
            child: const Text('Continue & Sign Up'),
          ),

          const SizedBox(height: 20),

          Text(
            'By continuing, you agree to our Terms of Service and Privacy Policy.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),

          GestureDetector(
            onTap: () {
              // Open privacy policy
            },
            child: Text(
              'Privacy Policy',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontSize: 12,
                decoration: TextDecoration.underline,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          if (authState.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Text(
                'Sign in failed. Please try again.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
