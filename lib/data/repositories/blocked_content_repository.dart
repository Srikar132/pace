import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:pace/data/models/blocked_content_model.dart';

class BlockedContentRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Document reference for blocked content
  DocumentReference _getBlockedContentDoc(String userId) {
    return _firestore.collection('blockedContent').doc(userId);
  }

  // Get blocked content for a user
  Future<BlockedContentModel?> getBlockedContent(String userId) async {
    try {
      final doc = await _getBlockedContentDoc(userId).get();

      if (!doc.exists) {
        // Return default empty model if document doesn't exist
        return BlockedContentModel();
      }

      return BlockedContentModel.fromFirestore(doc);
    } catch (e) {
      debugPrint('Error getting blocked content: $e');
      rethrow;
    }
  }

  // Get blocked content as stream for real-time updates
  Stream<BlockedContentModel> getBlockedContentStream(String userId) {
    return _getBlockedContentDoc(userId)
        .snapshots(includeMetadataChanges: false) // Changed to false for better real-time updates
        .map(
          (doc) {
            debugPrint('🔄 Firestore stream update for user $userId: doc exists = ${doc.exists}');
            if (doc.exists) {
              final model = BlockedContentModel.fromFirestore(doc);
              debugPrint('📋 Short form blocks in stream: ${model.shortFormBlocks}');
              return model;
            } else {
              return BlockedContentModel();
            }
          },
        );
  }

  // Set or update blocked content
  Future<void> setBlockedContent(
    String userId,
    BlockedContentModel blockedContent,
  ) async {
    try {
      await _getBlockedContentDoc(
        userId,
      ).set(blockedContent.toFirestore(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error setting blocked content: $e');
      rethrow;
    }
  }

  // Update specific fields
  Future<void> updateBlockedContent(
    String userId,
    Map<String, dynamic> updates,
  ) async {
    try {
      // Always update the lastUpdated field
      updates['lastUpdated'] = Timestamp.fromDate(DateTime.now());

      await _getBlockedContentDoc(userId).update(updates);
    } catch (e) {
      debugPrint('Error updating blocked content: $e');
      rethrow;
    }
  }

  // === PERMANENTLY BLOCKED APPS ===

  // Add permanently blocked app
  Future<void> addPermanentlyBlockedApp(String userId, String packageName) async {
    try {
      // CHANGE: Use .set with merge: true instead of .update
      await _getBlockedContentDoc(userId).set({
        'permanentlyBlockedApps': FieldValue.arrayUnion([packageName]),
        'lastUpdated': Timestamp.fromDate(DateTime.now()),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error adding permanently blocked app: $e');
      rethrow;
    }
  }

  // Remove permanently blocked app
  Future<void> removePermanentlyBlockedApp(
    String userId,
    String packageName,
  ) async {
    try {
      await _getBlockedContentDoc(userId).update({
        'permanentlyBlockedApps': FieldValue.arrayRemove([packageName]),
        'lastUpdated': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      debugPrint('Error removing permanently blocked app: $e');
      rethrow;
    }
  }

  // Set multiple permanently blocked apps
  Future<void> setPermanentlyBlockedApps(
    String userId,
    List<String> packageNames,
  ) async {
    try {
      await _getBlockedContentDoc(userId).update({
        'permanentlyBlockedApps': packageNames,
        'lastUpdated': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      debugPrint('Error setting permanently blocked apps: $e');
      rethrow;
    }
  }

  // === BLOCKED WEBSITES ===

  // === BLOCKED WEBSITES ===
  Future<void> addBlockedWebsite(String userId, BlockedWebsite website) async {
    try {
      final currentData = await getBlockedContent(userId);
      final currentWebsites = currentData?.blockedWebsites ?? [];

      final existingIndex = currentWebsites.indexWhere((w) => w.url == website.url);
      List<BlockedWebsite> updatedWebsites;
      if (existingIndex != -1) {
        updatedWebsites = List.from(currentWebsites);
        updatedWebsites[existingIndex] = website;
      } else {
        updatedWebsites = [...currentWebsites, website];
      }

      // CHANGE: Use .set with merge: true
      await _getBlockedContentDoc(userId).set({
        'blockedWebsites': updatedWebsites.map((w) => w.toMap()).toList(),
        'lastUpdated': Timestamp.fromDate(DateTime.now()),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error adding blocked website: $e');
      rethrow;
    }
  }

  // Remove blocked website
  Future<void> removeBlockedWebsite(String userId, String url) async {
    try {
      final currentData = await getBlockedContent(userId);
      final currentWebsites = currentData?.blockedWebsites ?? [];

      final updatedWebsites = currentWebsites
          .where((w) => w.url != url)
          .toList();

      await _getBlockedContentDoc(userId).update({
        'blockedWebsites': updatedWebsites.map((w) => w.toMap()).toList(),
        'lastUpdated': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      debugPrint('Error removing blocked website: $e');
      rethrow;
    }
  }

  // Set multiple blocked websites
  Future<void> setBlockedWebsites(
    String userId,
    List<BlockedWebsite> websites,
  ) async {
    try {
      await _getBlockedContentDoc(userId).update({
        'blockedWebsites': websites.map((w) => w.toMap()).toList(),
        'lastUpdated': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      debugPrint('Error setting blocked websites: $e');
      rethrow;
    }
  }

  // Toggle website block status
  Future<void> toggleWebsiteBlockStatus(
    String userId,
    String url,
    bool isActive,
  ) async {
    try {
      final currentData = await getBlockedContent(userId);
      final currentWebsites = currentData?.blockedWebsites ?? [];

      final updatedWebsites = currentWebsites.map((website) {
        if (website.url == url) {
          return BlockedWebsite(
            url: website.url,
            name: website.name,
            isActive: isActive,
          );
        }
        return website;
      }).toList();

      await _getBlockedContentDoc(userId).update({
        'blockedWebsites': updatedWebsites.map((w) => w.toMap()).toList(),
        'lastUpdated': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      debugPrint('Error toggling website block status: $e');
      rethrow;
    }
  }


// === SHORT FORM BLOCKS ===
  Future<void> setShortFormBlock(String userId, ShortFormBlock block) async {
    try {
      final key = '${block.platform}_${block.feature}';

      // CHANGE: Use .set with merge: true
      await _getBlockedContentDoc(userId).set({
        'shortFormBlocks.$key': block.toMap(),
        'lastUpdated': Timestamp.fromDate(DateTime.now()),
      }, SetOptions(merge: true));

    } catch (e) {
      debugPrint('Error setting short form block: $e');
      rethrow;
    }
  }

  // Remove short form block
  Future<void> removeShortFormBlock(
    String userId,
    String platform,
    String feature,
  ) async {
    try {
      final key = '${platform}_$feature';

      await _getBlockedContentDoc(userId).update({
        'shortFormBlocks.$key': FieldValue.delete(),
        'lastUpdated': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      debugPrint('Error removing short form block: $e');
      rethrow;
    }
  }

  // Set multiple short form blocks
  Future<void> setShortFormBlocks(
    String userId,
    Map<String, ShortFormBlock> blocks,
  ) async {
    try {
      final blocksMap = blocks.map(
        (key, value) => MapEntry(key, value.toMap()),
      );

      await _getBlockedContentDoc(userId).update({
        'shortFormBlocks': blocksMap,
        'lastUpdated': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      debugPrint('Error setting short form blocks: $e');
      rethrow;
    }
  }

  // Toggle short form block status
  Future<void> toggleShortFormBlockStatus(
    String userId,
    String platform,
    String feature,
    bool isBlocked,
  ) async {
    try {
      final key = '${platform}_$feature';

      // Get the document reference
      final docRef = _getBlockedContentDoc(userId);
      
      // Create the field path for nested update
      final fieldPath = 'shortFormBlocks.$key';
      
      // Use update with FieldPath to ensure proper Firestore change detection
      await docRef.update({
        fieldPath: {
          'platform': platform,
          'feature': feature,
          'isBlocked': isBlocked,
        },
        'lastUpdated': Timestamp.fromDate(DateTime.now()),
      });

      debugPrint('Successfully updated short form block: $key to $isBlocked');
    } catch (e) {
      debugPrint('Error toggling short form block status: $e');
      
      // If document doesn't exist, create it with the block
      if (e.toString().contains('not found') || e.toString().contains('No document')) {
        try {
          debugPrint('Document not found, creating new one...');
          final block = ShortFormBlock(
            platform: platform,
            feature: feature,
            isBlocked: isBlocked,
          );
          
          final blockKey = '${platform}_$feature';
          await _getBlockedContentDoc(userId).set({
            'shortFormBlocks': {blockKey: block.toMap()},
            'lastUpdated': Timestamp.fromDate(DateTime.now()),
          });
          
          debugPrint('Successfully created new blocked content document');
        } catch (createError) {
          debugPrint('Error creating document: $createError');
          rethrow;
        }
      } else {
        rethrow;
      }
    }
  }

  // === UTILITY METHODS ===

  // Check if app is blocked
  Future<bool> isAppBlocked(String userId, String packageName) async {
    try {
      final blockedContent = await getBlockedContent(userId);
      return blockedContent?.isAppBlocked(packageName) ?? false;
    } catch (e) {
      debugPrint('Error checking if app is blocked: $e');
      return false;
    }
  }

  // Check if website is blocked
  Future<bool> isWebsiteBlocked(String userId, String url) async {
    try {
      final blockedContent = await getBlockedContent(userId);
      return blockedContent?.isWebsiteBlocked(url) ?? false;
    } catch (e) {
      debugPrint('Error checking if website is blocked: $e');
      return false;
    }
  }

  // Check if short form is blocked
  Future<bool> isShortFormBlocked(
    String userId,
    String platform,
    String feature,
  ) async {
    try {
      final blockedContent = await getBlockedContent(userId);
      return blockedContent?.isShortFormBlocked(platform, feature) ?? false;
    } catch (e) {
      debugPrint('Error checking if short form is blocked: $e');
      return false;
    }
  }

  // Clear all blocked content for user (useful for logout)
  Future<void> clearBlockedContent(String userId) async {
    try {
      await _getBlockedContentDoc(userId).delete();
    } catch (e) {
      debugPrint('Error clearing blocked content: $e');
      rethrow;
    }
  }

  // Reset to default empty state
  Future<void> resetBlockedContent(String userId) async {
    try {
      final defaultContent = BlockedContentModel();
      await setBlockedContent(userId, defaultContent);
    } catch (e) {
      debugPrint('Error resetting blocked content: $e');
      rethrow;
    }
  }
}