import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/data/models/blocked_content_model.dart';
import 'package:pace/presentation/providers/auth_provider.dart';
import 'package:pace/presentation/providers/blocked_content_provider.dart';

/// Example widget showing how to use the persistent blocking system
class PersistentBlockingControl extends ConsumerWidget {
  const PersistentBlockingControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    
    if (user == null) {
      return const Center(child: Text('Please log in first'));
    }

    final notifier = ref.watch(blockedContentNotifierProvider.notifier);
    final blockingSummary = ref.watch(blockingSummaryProvider(user.uid));
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Persistent Blocking Control'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Blocking Status',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    _buildStatusRow('Apps', blockingSummary['apps'] ?? false),
                    _buildStatusRow('Websites', blockingSummary['websites'] ?? false),
                    _buildStatusRow('Short Form', blockingSummary['shortForm'] ?? false),
                    _buildStatusRow('Notifications', blockingSummary['notifications'] ?? false),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // App Blocking Controls
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'App Blocking Control',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    
                    // Native Status
                    Consumer(
                      builder: (context, ref, child) {
                        final nativeStatus = ref.watch(nativePersistentAppBlockingProvider);
                        return nativeStatus.when(
                          data: (enabled) => Row(
                            children: [
                              Icon(
                                enabled ? Icons.block : Icons.check_circle,
                                color: enabled ? Colors.red : Colors.green,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Native Blocking: ${enabled ? 'Active' : 'Inactive'}',
                              ),
                            ],
                          ),
                          loading: () => const CircularProgressIndicator(),
                          error: (error, stack) => Text('Error: $error'),
                        );
                      },
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Quick Toggle Buttons
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: () => _enableAppBlocking(notifier, user.uid),
                          child: const Text('Enable App Blocking'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _disableAppBlocking(notifier, user.uid),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Disable App Blocking'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Website Blocking Controls
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Website Blocking Control',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: () => _enableWebsiteBlocking(notifier, user.uid),
                          child: const Text('Enable Website Blocking'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _disableWebsiteBlocking(notifier, user.uid),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Disable Website Blocking'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Sync Controls
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sync Controls',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: () => notifier.syncFirestoreToNative(user.uid),
                          child: const Text('Firestore → Native'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => notifier.syncNativeToFirestore(user.uid),
                          child: const Text('Native → Firestore'),
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
    );
  }
  
  Widget _buildStatusRow(String label, bool isActive) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Icon(
            isActive ? Icons.check_circle : Icons.cancel,
            color: isActive ? Colors.green : Colors.grey,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text('$label: ${isActive ? 'Active' : 'Inactive'}'),
        ],
      ),
    );
  }
  
  Future<void> _enableAppBlocking(BlockedContentNotifier notifier, String userId) async {
    // Example: Block Instagram and TikTok
    const blockedApps = [
      'com.instagram.android',
      'com.zhiliaoapp.musically', // TikTok
      'com.facebook.katana', // Facebook
    ];
    
    await notifier.setPersistentAppBlocking(
      userId: userId,
      enabled: true,
      blockedApps: blockedApps,
    );
  }
  
  Future<void> _disableAppBlocking(BlockedContentNotifier notifier, String userId) async {
    await notifier.setPersistentAppBlocking(
      userId: userId,
      enabled: false,
      blockedApps: [],
    );
  }
  
  Future<void> _enableWebsiteBlocking(BlockedContentNotifier notifier, String userId) async {
    // Example: Block social media websites
    final blockedWebsites = [
      BlockedWebsite(
        url: 'facebook.com',
        name: 'Facebook',
        isActive: true,
      ),
      BlockedWebsite(
        url: 'twitter.com',
        name: 'Twitter',
        isActive: true,
      ),
    ];
    
    await notifier.setPersistentWebsiteBlocking(
      userId: userId,
      enabled: true,
      blockedWebsites: blockedWebsites,
    );
  }
  
  Future<void> _disableWebsiteBlocking(BlockedContentNotifier notifier, String userId) async {
    await notifier.setPersistentWebsiteBlocking(
      userId: userId,
      enabled: false,
      blockedWebsites: [],
    );
  }
}
