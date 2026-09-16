import 'package:hive_flutter/hive_flutter.dart';
import 'package:pace/data/models/user_model.dart';

class HiveService {
  static const String userBoxName = 'user_box';
  static const String settingsBoxName = 'settings_box';
  static const String onboardingBoxName = 'onboarding_box';

  // Initialize Hive
  static Future<void> init() async {
    await Hive.initFlutter();
    
    // Register adapters
    // Hive.registerAdapter(UserModelAdapter());
    
    // Open boxes
    await Hive.openBox<UserModel>(userBoxName);
    await Hive.openBox(settingsBoxName);
    await Hive.openBox(onboardingBoxName);
  }

  // User Box operations
  static Box<UserModel> get userBox => Hive.box<UserModel>(userBoxName);
  
  static Future<void> saveUser(UserModel user) async {
    await userBox.put('current_user', user);
  }
  
  static UserModel? getCurrentUser() {
    return userBox.get('current_user');
  }
  
  static Future<void> deleteUser() async {
    await userBox.delete('current_user');
  }
  
  static bool hasUser() {
    return userBox.containsKey('current_user');
  }

  // Settings Box operations
  static Box get settingsBox => Hive.box(settingsBoxName);
  
  static Future<void> saveSetting(String key, dynamic value) async {
    await settingsBox.put(key, value);
  }
  
  static dynamic getSetting(String key, {dynamic defaultValue}) {
    return settingsBox.get(key, defaultValue: defaultValue);
  }

  // Onboarding Box operations
  static Box get onboardingBox => Hive.box(onboardingBoxName);
  
  static Future<void> markOnboardingComplete() async {
    await onboardingBox.put('onboarding_complete', true);
  }
  
  static bool hasCompletedOnboarding() {
    return onboardingBox.get('onboarding_complete', defaultValue: false);
  }

  // Clear all data (for logout)
  static Future<void> clearAllData() async {
    await userBox.clear();
    await settingsBox.clear();
    await onboardingBox.clear();
  }
}