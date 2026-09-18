import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/presentation/providers/background_image_provider.dart';
import 'package:pace/widgets/bottom_sheet_darg_handler.dart';

class BackgroundImageSelector extends ConsumerWidget {
  const BackgroundImageSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backgroundState = ref.watch(backgroundImageProvider);
    final availableBackgrounds = ref.watch(availableBackgroundsProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with close button
          // Background image selector
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Current Background Info
                  // Current Background Info
                  BottomSheetDragHandle(),

                  const SizedBox(height: 12),
                  // Background Grid
                  const Text(
                    'Choose Background',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 16 / 9,
                    ),
                    itemCount: availableBackgrounds.length,
                    itemBuilder: (context, index) {
                      final background = availableBackgrounds[index];
                      final imagePath = background['path']!;
                      final imageName = background['name']!;
                      final isSelected =
                          imagePath == backgroundState.currentBackground;

                      return GestureDetector(
                        onTap: backgroundState.isLoading
                            ? null
                            : () {
                                ref
                                    .read(backgroundImageProvider.notifier)
                                    .changeBackgroundImage(imagePath);
                              },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.blue
                                  : Colors.grey.shade300,
                              width: isSelected ? 3 : 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.asset(
                                  imagePath,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: Colors.grey.shade200,
                                      child: const Icon(
                                        Icons.image_not_supported,
                                        color: Colors.grey,
                                        size: 40,
                                      ),
                                    );
                                  },
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black.withValues(alpha: 0.7),
                                      ],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 8,
                                  left: 8,
                                  right: 8,
                                  child: Text(
                                    imageName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                if (isSelected)
                                  const Positioned(
                                    top: 8,
                                    right: 8,
                                    child: CircleAvatar(
                                      radius: 12,
                                      backgroundColor: Colors.blue,
                                      child: Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                if (backgroundState.isLoading)
                                  Container(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
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

// Helper widget to display current background as page background
class BackgroundImageContainer extends ConsumerWidget {
  final Widget child;
  final BoxFit fit;

  const BackgroundImageContainer({
    super.key,
    required this.child,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentBackground = ref.watch(currentBackgroundImageProvider);

    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(image: AssetImage(currentBackground), fit: fit),
      ),
      child: child,
    );
  }
}

// Simple widget to just get current background path
class CurrentBackgroundImage extends ConsumerWidget {
  const CurrentBackgroundImage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentBackground = ref.watch(currentBackgroundImageProvider);

    return Image.asset(
      currentBackground,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.grey.shade200,
          child: const Icon(
            Icons.image_not_supported,
            color: Colors.grey,
            size: 40,
          ),
        );
      },
    );
  }
}
