import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/widgets/background_image_selector.dart';
import 'package:pace/presentation/providers/background_image_provider.dart';

class BackgroundSettingsScreen extends ConsumerWidget {
  const BackgroundSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Background Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: BackgroundImageContainer(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.3),
                Colors.black.withOpacity(0.7),
              ],
            ),
          ),
          child: const SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16.0),
              child: BackgroundImageSelector(),
            ),
          ),
        ),
      ),
    );
  }
}

// Example of how to use the background as a page container
class ExampleHomeScreen extends ConsumerWidget {
  const ExampleHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentBackgroundName = ref.watch(currentBackgroundNameProvider);
    
    return Scaffold(
      body: BackgroundImageContainer(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.2),
                Colors.black.withOpacity(0.6),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                AppBar(
                  title: const Text('Pace'),
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Welcome to Pace',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Current Theme: $currentBackgroundName',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            FloatingActionButton.extended(
                              onPressed: () {
                                ref.read(backgroundImageProvider.notifier)
                                    .previousBackground();
                              },
                              icon: const Icon(Icons.skip_previous),
                              label: const Text('Previous'),
                            ),
                            FloatingActionButton.extended(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const BackgroundSettingsScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.settings),
                              label: const Text('Settings'),
                            ),
                            FloatingActionButton.extended(
                              onPressed: () {
                                ref.read(backgroundImageProvider.notifier)
                                    .nextBackground();
                              },
                              icon: const Icon(Icons.skip_next),
                              label: const Text('Next'),
                            ),
                          ],
                        ),
                      ],
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
