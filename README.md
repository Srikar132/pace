# pace

## 🎯 **Best Practices for Your App**

### **1. Offline-First Approach**

```dart
// Always use snapshots with metadata changes
.snapshots(includeMetadataChanges: true)

// Check if data is from cache
snapshot.metadata.isFromCache // true = offline data  

// Handle offline state in UI
if (snapshot.metadata.isFromCache) {
  // Show offline indicator
}
```

### **2. Optimize Reads**

```dart
// ❌ BAD: Multiple reads
final user = await _firestore.collection('users').doc(userId).get();
final settings = await _firestore.collection('userSettings').doc(userId).get();
final stats = await _firestore.collection('dailyStats').doc(userId).get();

// ✅ GOOD: Use streams and cache
final userStream = _firestore.collection('users').doc(userId).snapshots();
// Firebase caches automatically!
```

### **3. Batch Updates**

```dart
// ✅ ALWAYS use batches for multiple updates
final batch = _firestore.batch();

batch.update(userRef, {...});
batch.set(sessionRef, {...});
batch.update(statsRef, {...});

await batch.commit(); // Single network call!
```

### **4. Handle Offline Errors Gracefully**

```dart
try {
  await _firestore.collection('users').doc(userId).update({...});
} on FirebaseException catch (e) {
  if (e.code == 'unavailable') {
    // Network error - data will sync when online
    debugPrint('Offline: Changes will sync when online');
  } else {
    rethrow;
  }
}
```

### **5. Clear Cache on Logout**

```dart
// In your AuthRepository signOut method
Future<void> signOut() async {
  try {
    // Clear Firestore cache
    await FirebaseFirestore.instance.clearPersistence();
    
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  } catch (e) {
    debugPrint('Error signing out: $e');
    rethrow;
  }
}