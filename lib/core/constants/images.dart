// WELCOME SCREEN IMAGES
String get kWelcomeBackgroundImage => 'assets/images/entry_bg.jpg';

// SOCIAL ICONS
String get kGoogleLogoImage => 'assets/images/google_icon.png';

// HOME
String get kHomeBackgroundImage => 'assets/images/home-bg1.png';

String get KLumoIcon => 'assets/images/mascot.png';

// AVAILABLE BACKGROUND IMAGES FROM ASSETS
String get kBackgroundImage1 => 'assets/images/entry_bg.jpg';
String get kBackgroundImage2 => 'assets/images/home-bg1.png';
String get kBackgroundImage3 => 'assets/images/image.png';
String get kBackgroundImage4 => 'assets/images/song-image1.png';
String get kBackgroundImage5 => 'assets/images/song-image2.png';

class BackgroundImageConstants {
  static const String defaultBackground = 'assets/images/home-bg1.png';

  static const List<String> availableBackgrounds = [
    'assets/images/home-bg1.png',
    'assets/images/entry_bg.jpg',
    'assets/images/theme1.png',
    'assets/images/theme2.png',
    'assets/images/theme3.png',
    'assets/images/theme4.png',
    'assets/images/theme5.png',
    'assets/images/theme6.png',
  ];

  static const List<String> backgroundNames = [
    'Ocean Waves',
    'Galaxy Stars',
    'Mountain Peaks',
    'Cherry Blossoms',
    'Sunset Valley',
    'Desert Dunes',
    'Forest Trail',
    'City Lights',
    'Rainy Day',
  ];

  // Get all backgrounds with their display names
  static List<Map<String, String>> get backgroundsWithNames {
    return List.generate(availableBackgrounds.length, (index) {
      return {
        'path': availableBackgrounds[index],
        'name': backgroundNames[index],
      };
    });
  }

  // Get background name by path
  static String getBackgroundName(String path) {
    final index = availableBackgrounds.indexOf(path);
    return index != -1 ? backgroundNames[index] : 'Unknown';
  }
}
