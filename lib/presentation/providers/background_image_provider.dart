import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:pace/core/constants/images.dart';
import 'package:pace/presentation/providers/auth_provider.dart';

// Background Image State
class BackgroundImageState {
  final String currentBackground;
  final bool isLoading;
  final String? error;

  const BackgroundImageState({
    required this.currentBackground,
    this.isLoading = false,
    this.error,
  });

  BackgroundImageState copyWith({
    String? currentBackground,
    bool? isLoading,
    String? error,
  }) {
    return BackgroundImageState(
      currentBackground: currentBackground ?? this.currentBackground,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// Background Image Repository
class BackgroundImageRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'userSettings';

  // Get background image from Firestore
  Stream<String> streamBackgroundImage(String userId) {
    return _firestore
        .collection(_collection)
        .doc(userId)
        .snapshots(includeMetadataChanges: true)
        .map((doc) {
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        return data['backgroundImage'] as String? ?? BackgroundImageConstants.defaultBackground;
      }
      return BackgroundImageConstants.defaultBackground;
    });
  }

  // Update background image in Firestore
  Future<void> updateBackgroundImage(String userId, String imagePath) async {
    try {
      await _firestore
          .collection(_collection)
          .doc(userId)
          .set({
        'backgroundImage': imagePath,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      debugPrint('Background image updated successfully: $imagePath');
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        debugPrint('Offline: Background image will sync when online');
        // Firebase handles offline persistence automatically
      } else {
        debugPrint('Error updating background image: $e');
        rethrow;
      }
    } catch (e) {
      debugPrint('Error updating background image: $e');
      rethrow;
    }
  }

  // Get cached background image (for instant access)
  String? getCachedBackgroundImage(String userId) {
    try {
      // This would return cached data from Firebase's local cache
      // For now, we'll return null to force using the stream
      return null;
    } catch (e) {
      debugPrint('Error getting cached background image: $e');
      return BackgroundImageConstants.defaultBackground;
    }
  }
}

// Background Image Notifier
class BackgroundImageNotifier extends Notifier<BackgroundImageState> {
  BackgroundImageRepository? _repository;
  String? _currentUserId;

  BackgroundImageRepository get repository {
    _repository ??= BackgroundImageRepository();
    return _repository!;
  }

  @override
  BackgroundImageState build() {
    // Listen to auth state changes
    ref.listen(currentUserProvider, (previous, next) {
      final user = next.value;
      if (user?.uid != _currentUserId) {
        _currentUserId = user?.uid;
        if (_currentUserId != null) {
          _loadBackgroundImage(_currentUserId!);
        } else {
          // User logged out, reset to default
          state = BackgroundImageState(
            currentBackground: BackgroundImageConstants.defaultBackground,
          );
        }
      }
    });

    // Get current user and load background
    final user = ref.read(currentUserProvider).value;
    _currentUserId = user?.uid;
    
    if (_currentUserId != null) {
      _loadBackgroundImage(_currentUserId!);
    }

    return BackgroundImageState(
      currentBackground: BackgroundImageConstants.defaultBackground,
    );
  }

  void _loadBackgroundImage(String userId) {
    // Listen to background image changes from Firestore stream
    ref.listen(
      backgroundImageStreamProvider(userId),
      (previous, next) {
        next.whenOrNull(
          data: (background) {
            state = state.copyWith(
              currentBackground: background,
              isLoading: false,
              error: null,
            );
          },
          error: (error, stackTrace) {
            state = state.copyWith(
              isLoading: false,
              error: error.toString(),
            );
          },
        );
      },
    );
  }

  // Change background image
  Future<void> changeBackgroundImage(String imagePath) async {
    if (_currentUserId == null) {
      state = state.copyWith(error: 'User not authenticated');
      return;
    }

    // Validate image path
    if (!BackgroundImageConstants.availableBackgrounds.contains(imagePath)) {
      state = state.copyWith(error: 'Invalid background image selected');
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      // Update immediately for UI responsiveness
      state = state.copyWith(
        currentBackground: imagePath,
        isLoading: false,
      );

      // Update in Firestore
      await repository.updateBackgroundImage(_currentUserId!, imagePath);
      
      debugPrint('✅ Background image changed to: $imagePath');
    } catch (e) {
      // Revert on error
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to update background image: $e',
      );
      debugPrint('❌ Error changing background image: $e');
    }
  }

  // Get next background image (for cycling through)
  String getNextBackgroundImage() {
    final currentIndex = BackgroundImageConstants.availableBackgrounds
        .indexOf(state.currentBackground);
    
    if (currentIndex == -1) {
      return BackgroundImageConstants.availableBackgrounds.first;
    }
    
    final nextIndex = (currentIndex + 1) % 
        BackgroundImageConstants.availableBackgrounds.length;
    
    return BackgroundImageConstants.availableBackgrounds[nextIndex];
  }

  // Get previous background image (for cycling through)
  String getPreviousBackgroundImage() {
    final currentIndex = BackgroundImageConstants.availableBackgrounds
        .indexOf(state.currentBackground);
    
    if (currentIndex == -1) {
      return BackgroundImageConstants.availableBackgrounds.last;
    }
    
    final previousIndex = currentIndex == 0 
        ? BackgroundImageConstants.availableBackgrounds.length - 1
        : currentIndex - 1;
    
    return BackgroundImageConstants.availableBackgrounds[previousIndex];
  }

  // Cycle to next background
  Future<void> nextBackground() async {
    final nextImage = getNextBackgroundImage();
    await changeBackgroundImage(nextImage);
  }

  // Cycle to previous background
  Future<void> previousBackground() async {
    final previousImage = getPreviousBackgroundImage();
    await changeBackgroundImage(previousImage);
  }

  // Reset to default background
  Future<void> resetToDefault() async {
    await changeBackgroundImage(BackgroundImageConstants.defaultBackground);
  }
}

// Providers
final backgroundImageRepositoryProvider = Provider<BackgroundImageRepository>((ref) {
  return BackgroundImageRepository();
});

final backgroundImageProvider = NotifierProvider<BackgroundImageNotifier, BackgroundImageState>(() {
  return BackgroundImageNotifier();
});

// Stream provider for real-time background updates
final backgroundImageStreamProvider = StreamProvider.family<String, String>((ref, userId) {
  return ref.watch(backgroundImageRepositoryProvider).streamBackgroundImage(userId);
});

// Quick access providers
final currentBackgroundImageProvider = Provider<String>((ref) {
  return ref.watch(backgroundImageProvider).currentBackground;
});

final isBackgroundImageLoadingProvider = Provider<bool>((ref) {
  return ref.watch(backgroundImageProvider).isLoading;
});

final backgroundImageErrorProvider = Provider<String?>((ref) {
  return ref.watch(backgroundImageProvider).error;
});

// Helper provider for available backgrounds with names
final availableBackgroundsProvider = Provider<List<Map<String, String>>>((ref) {
  return BackgroundImageConstants.backgroundsWithNames;
});

// Helper provider for current background name
final currentBackgroundNameProvider = Provider<String>((ref) {
  final currentPath = ref.watch(currentBackgroundImageProvider);
  return BackgroundImageConstants.getBackgroundName(currentPath);
});
