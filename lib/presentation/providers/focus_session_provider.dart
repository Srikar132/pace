import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pace/data/models/focus_session_model.dart';
import 'package:pace/services/native_service.dart';
import 'package:pace/presentation/providers/auth_provider.dart';
import 'package:pace/data/repositories/focus_session_repository.dart';

final sessionRepositoryProvider = Provider<FocusSessionRepository>((ref) {
  return FocusSessionRepository();
});

final todaySessionsProvider =
    StreamProvider.family<List<FocusSessionModel>, String>((ref, userId) {
      return ref.watch(sessionRepositoryProvider).streamTodaySessions(userId);
    });

// ============================================================================
// FOCUS SESSION STATE
// ============================================================================

enum FocusSessionStatus {
  idle,
  starting,
  active,
  paused,
  ending,
  endingWithSave,
  completed,
  error,
}

class FocusSessionState {
  final FocusSessionStatus status;
  final String? sessionId;
  final int? elapsedSeconds;
  final int? remainingSeconds;
  final int? plannedDuration;
  final String? sessionType;
  final bool isPaused;
  final String? error;
  final Map<String, dynamic>? nativeSessionData;
  // Authoritative completion data from native's 'session_completed'/'session_auto_completed'
  // event (actualDuration, completionRate, totalElapsed) - captured whenever the event
  // arrives, regardless of whether it triggers auto-completion navigation.
  final Map<String, dynamic>? completionData;

  FocusSessionState({
    this.status = FocusSessionStatus.idle,
    this.sessionId,
    this.elapsedSeconds,
    this.remainingSeconds,
    this.plannedDuration,
    this.sessionType,
    this.isPaused = false,
    this.error,
    this.nativeSessionData,
    this.completionData,
  });

  FocusSessionState copyWith({
    FocusSessionStatus? status,
    String? sessionId,
    int? elapsedSeconds,
    int? remainingSeconds,
    int? plannedDuration,
    String? sessionType,
    bool? isPaused,
    String? error,
    Map<String, dynamic>? nativeSessionData,
    Map<String, dynamic>? completionData,
  }) {
    return FocusSessionState(
      status: status ?? this.status,
      sessionId: sessionId ?? this.sessionId,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      plannedDuration: plannedDuration ?? this.plannedDuration,
      sessionType: sessionType ?? this.sessionType,
      isPaused: isPaused ?? this.isPaused,
      error: error,
      nativeSessionData: nativeSessionData ?? this.nativeSessionData,
      completionData: completionData ?? this.completionData,
    );
  }

  bool get isActive =>
      status == FocusSessionStatus.active ||
      status == FocusSessionStatus.paused;
  int get elapsedMinutes => (elapsedSeconds ?? 0) ~/ 60;
  int get remainingMinutes => (remainingSeconds ?? 0) ~/ 60;
}

// ============================================================================
// FOCUS SESSION NOTIFIER
// ============================================================================

class FocusSessionNotifier extends Notifier<FocusSessionState> {
  StreamSubscription? _eventSubscription;
  Timer? _localTimer;

  // KEY FIX: Single source of truth for manual ending
  bool _isManuallyEnding = false;

  @override
  FocusSessionState build() {
    _listenToNativeEvents();
    ref.onDispose(() {
      _eventSubscription?.cancel();
      _stopLocalTimer();
    });
    return FocusSessionState();
  }

  void _listenToNativeEvents() {
    _eventSubscription = NativeService.focusEventStream.listen(
      (event) {
        try {
          final eventType = event['event'] as String?;
          final data = _safeConvertToMap(event['data']);

          debugPrint(
            '📡 Native event: $eventType | Manual ending: $_isManuallyEnding',
          );

          switch (eventType) {
            case 'session_started':
              _handleSessionStarted(data);
              break;
            case 'session_paused':
              _handleSessionPaused(data);
              break;
            case 'session_resumed':
              _handleSessionResumed(data);
              break;
            case 'session_completed':
            case 'session_auto_completed':
              // Always capture native's authoritative completion data (actualDuration,
              // completionRate) so the eventual save - manual or auto - uses real
              // wall-clock time instead of the Dart-side local timer.
              if (data != null) {
                state = state.copyWith(completionData: data);
              }
              // KEY FIX: Only auto-save if not manually ending
              if (!_isManuallyEnding) {
                _handleAutoCompletion(data);
              } else {
                debugPrint(
                  '🛑 Ignoring auto-completion navigation - manual ending in progress (data captured)',
                );
              }
              break;
            case 'timer_update':
              _handleTimerUpdate(data);
              break;
            case 'interruption_detected':
              _handleInterruptionDetected(data);
              break;
          }
        } catch (e, stack) {
          debugPrint('❌ Error processing native event: $e');
          debugPrint('Stack trace: $stack');
        }
      },
      onError: (error) {
        debugPrint('❌ Error in native event stream: $error');
      },
    );
  }

  Map<String, dynamic>? _safeConvertToMap(dynamic data) {
    if (data == null) return null;

    try {
      if (data is Map<String, dynamic>) {
        return data;
      } else if (data is Map) {
        return Map<String, dynamic>.from(
          data.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } catch (e) {
      debugPrint('⚠️ Error converting map: $e');
    }

    return null;
  }

  void _handleSessionStarted(Map<String, dynamic>? data) {
    if (data == null) return;

    state = state.copyWith(
      status: FocusSessionStatus.active,
      sessionId: data['sessionId'] as String?,
      sessionType: data['sessionType'] as String?,
      plannedDuration: _safeInt(data['plannedDuration']),
      isPaused: false,
      nativeSessionData: data,
    );

    _startLocalTimer();
  }

  void _handleSessionPaused(Map<String, dynamic>? data) {
    state = state.copyWith(status: FocusSessionStatus.paused, isPaused: true);
    _stopLocalTimer();
  }

  void _handleSessionResumed(Map<String, dynamic>? data) {
    state = state.copyWith(status: FocusSessionStatus.active, isPaused: false);
    _startLocalTimer();
  }

  // KEY FIX: Separate handler for auto-completion (timer finished naturally)
  void _handleAutoCompletion(Map<String, dynamic>? data) {
    debugPrint('🔄 Auto-completion detected - saving and going to home');

    state = state.copyWith(
      status: FocusSessionStatus.completed,
      isPaused: false,
    );
    _stopLocalTimer();

    // Auto-save without user input
    if (data != null) {
      _saveCompletedSession(data);
    }
  }

  void _handleTimerUpdate(Map<String, dynamic>? data) {
    if (data == null) return;

    final elapsedMs = _safeInt(data['elapsed']);
    final remainingMs = _safeInt(data['remaining']);

    state = state.copyWith(
      elapsedSeconds: elapsedMs != null ? elapsedMs ~/ 1000 : null,
      remainingSeconds: remainingMs != null ? remainingMs ~/ 1000 : null,
    );
  }

  void _handleInterruptionDetected(Map<String, dynamic>? data) {
    if (data == null) return;
    debugPrint('⚠️ Interruption detected: ${data['appName']}');
  }

  int? _safeInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  void _startLocalTimer() {
    _stopLocalTimer();
    _localTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!state.isPaused && state.isActive) {
        final newElapsed = (state.elapsedSeconds ?? 0) + 1;
        final newRemaining = state.remainingSeconds != null
            ? (state.remainingSeconds! - 1).clamp(0, double.infinity).toInt()
            : null;

        state = state.copyWith(
          elapsedSeconds: newElapsed,
          remainingSeconds: newRemaining,
        );
      }
    });
  }

  void _stopLocalTimer() {
    _localTimer?.cancel();
    _localTimer = null;
  }

  String _getTodayDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  // ============================================================================
  // SESSION CONTROL
  // ============================================================================

  Future<void> startSession({
    required int plannedDuration,
    required String sessionType,
    required List<String> blockedApps,
    List<Map<String, dynamic>>? blockedWebsites,
    bool shortFormBlocked = false,
    bool notificationsBlocked = false,
  }) async {
    state = state.copyWith(status: FocusSessionStatus.starting);

    try {
      final user = ref.read(currentUserProvider).value;
      if (user == null) throw Exception('User not logged in');

      final nativeSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      final todayDate = _getTodayDateString();

      final success = await NativeService.startFocusSession(
        sessionId: nativeSessionId,
        userId: user.uid,
        plannedDuration: plannedDuration,
        sessionType: sessionType,
        blockedApps: blockedApps,
        blockedWebsites: blockedWebsites,
        shortFormBlocked: shortFormBlocked,
        notificationsBlocked: notificationsBlocked,
      );

      if (!success) throw Exception('Failed to start native session');

      final sessionModel = FocusSessionModel(
        sessionId: nativeSessionId,
        userId: user.uid,
        startTime: DateTime.now(),
        plannedDuration: plannedDuration,
        sessionType: sessionType,
        status: 'active',
        date: todayDate,
      );

      final firestoreId = await ref
          .read(sessionRepositoryProvider)
          .createSession(sessionModel);

      state = state.copyWith(
        status: FocusSessionStatus.active,
        sessionId: firestoreId,
        plannedDuration: plannedDuration,
        sessionType: sessionType,
        elapsedSeconds: 0,
        remainingSeconds: plannedDuration * 60,
        isPaused: false,
      );

      _startLocalTimer();
    } catch (e) {
      debugPrint('❌ Error starting session: $e');
      state = state.copyWith(
        status: FocusSessionStatus.error,
        error: e.toString(),
      );
    }
  }

  Future<void> pauseSession() async {
    if (!state.isActive || state.isPaused) return;

    final success = await NativeService.pauseFocusSession();
    if (success) {
      state = state.copyWith(status: FocusSessionStatus.paused, isPaused: true);
      _stopLocalTimer();
    }
  }

  Future<void> resumeSession() async {
    if (!state.isActive || !state.isPaused) return;

    final success = await NativeService.resumeFocusSession();
    if (success) {
      state = state.copyWith(
        status: FocusSessionStatus.active,
        isPaused: false,
      );
      _startLocalTimer();
    }
  }

  // KEY FIX: Simplified endSession - just set flag and state
  Future<void> endSession() async {
    if (!state.isActive) {
      debugPrint('⚠️ No active session to end');
      return;
    }

    debugPrint('🎯 Manual end session initiated');

    // Set flag FIRST to block any incoming auto-completion events
    _isManuallyEnding = true;

    try {
      // Stop native session
      final success = await NativeService.endFocusSession();

      if (success) {
        // Stop timer
        _stopLocalTimer();

        // Set state to trigger navigation to save screen
        state = state.copyWith(status: FocusSessionStatus.endingWithSave);

        debugPrint('✅ Session ended - navigating to save screen');
        return;
      }

      // Native returned false - this can legitimately happen if its own timer
      // auto-completed in the narrow window between our isActive check and this
      // call landing. Check whether native actually has no active session left;
      // if so, treat this as a completed session instead of losing it to an error.
      final status = await NativeService.getCurrentSessionStatus();
      final stillActiveNatively = status != null && status['isActive'] == true;

      if (!stillActiveNatively) {
        debugPrint(
          '⚠️ Native session already completed (race) - treating as ended',
        );
        _stopLocalTimer();
        state = state.copyWith(status: FocusSessionStatus.endingWithSave);
        return;
      }

      throw Exception('Failed to end native session');
    } catch (e) {
      debugPrint('❌ Error ending session: $e');
      _isManuallyEnding = false;
      state = FocusSessionState(
        status: FocusSessionStatus.error,
        error: e.toString(),
      );
      _stopLocalTimer();
    }
  }

  Future<void> refreshSessionFromNative() async {
    try {
      final status = await NativeService.getCurrentSessionStatus();

      if (status != null && status['isActive'] == true) {
        final mappedData = _safeConvertToMap(status);
        if (mappedData == null) return;

        // Unlike a fresh session_started event (always 0 elapsed),
        // getCurrentSessionStatus() reports how far into the session we
        // actually are (key is 'elapsedTime', in ms - different from the
        // 'elapsed' key timer_update events use). Thread it through instead
        // of falling back to _handleSessionStarted, which always resets to
        // 0:00 and would ignore whatever time already passed before this
        // cold start / process restart picked the session back up.
        final plannedDuration = _safeInt(mappedData['plannedDuration']);
        final elapsedMs = _safeInt(mappedData['elapsedTime']);
        final elapsedSeconds = elapsedMs != null ? elapsedMs ~/ 1000 : 0;
        final remainingSeconds = plannedDuration != null
            ? ((plannedDuration * 60) - elapsedSeconds).clamp(
                0,
                plannedDuration * 60,
              )
            : null;
        final isPaused = mappedData['isPaused'] == true;

        state = state.copyWith(
          status: isPaused
              ? FocusSessionStatus.paused
              : FocusSessionStatus.active,
          sessionId: mappedData['sessionId'] as String?,
          sessionType: mappedData['sessionType'] as String?,
          plannedDuration: plannedDuration,
          elapsedSeconds: elapsedSeconds,
          remainingSeconds: remainingSeconds,
          isPaused: isPaused,
          nativeSessionData: mappedData,
        );

        if (!isPaused) {
          _startLocalTimer();
        }

        debugPrint(
          '🔄 Focus session synchronized from Native '
          '(elapsed: ${elapsedSeconds}s, type: ${mappedData['sessionType']})',
        );
      } else if (state.isActive) {
        state = FocusSessionState(status: FocusSessionStatus.idle);
        _stopLocalTimer();
      }
    } catch (e) {
      debugPrint('❌ Sync Error: $e');
    }
  }

  Future<void> _saveCompletedSession(Map<String, dynamic> data) async {
    try {
      final user = ref.read(currentUserProvider).value;
      if (user == null || state.sessionId == null) return;

      // Prefer native's wall-clock actualDuration over the Dart local timer,
      // which can drift if the engine was throttled/backgrounded mid-session.
      final actualDuration =
          _safeInt(data['actualDuration']) ?? state.elapsedMinutes;
      final todayDate = _getTodayDateString();
      final completionRate = _computeCompletionRate(actualDuration);

      await ref
          .read(sessionRepositoryProvider)
          .completeSession(
            sessionId: state.sessionId!,
            userId: user.uid,
            actualDuration: actualDuration,
            completionRate: completionRate,
            date: todayDate,
          );

      debugPrint('✅ Session auto-saved to Firestore');
    } catch (e) {
      debugPrint('❌ Error saving completed session: $e');
    }
  }

  double _computeCompletionRate(int actualDuration) {
    final plannedDuration = state.plannedDuration ?? 0;
    if (plannedDuration <= 0) return 100.0;
    return (actualDuration / plannedDuration * 100).clamp(0, 100).toDouble();
  }

  Map<String, dynamic> getCurrentSessionData() {
    return {
      'sessionId': state.sessionId,
      'elapsedSeconds': state.elapsedSeconds ?? 0,
      'plannedDuration': state.plannedDuration,
      'sessionType': state.sessionType,
      'startTime': DateTime.now().subtract(
        Duration(seconds: state.elapsedSeconds ?? 0),
      ),
    };
  }

  // KEY FIX: Reset flag when saving with notes
  Future<void> completeSessionWithNotes({String? notes, String? tag}) async {
    try {
      final user = ref.read(currentUserProvider).value;
      if (user == null || state.sessionId == null) return;

      // Prefer native's wall-clock actualDuration (captured from the
      // session_completed event, even when its navigation was ignored during
      // manual ending) over the Dart local timer.
      final actualDuration =
          _safeInt(state.completionData?['actualDuration']) ??
          state.elapsedMinutes;
      final todayDate = _getTodayDateString();
      final completionRate = _computeCompletionRate(actualDuration);

      await ref
          .read(sessionRepositoryProvider)
          .updateSession(state.sessionId!, {
            'actualDuration': actualDuration,
            'completionRate': completionRate,
            'endTime': Timestamp.now(),
            'status': 'completed',
            'notes': notes ?? '',
            'tag': tag ?? 'untagged',
            'completedAt': todayDate,
          });

      // Reset flag and state
      _isManuallyEnding = false;
      state = FocusSessionState(status: FocusSessionStatus.completed);
      _stopLocalTimer();

      debugPrint('✅ Session completed and saved with notes');
    } catch (e) {
      debugPrint('❌ Error completing session with notes: $e');
      _isManuallyEnding = false;
      rethrow;
    }
  }

  // KEY FIX: Reset flag when discarding
  void discardSession() {
    try {
      final sessionId = state.sessionId;

      _isManuallyEnding = false;
      state = FocusSessionState(status: FocusSessionStatus.idle);
      _stopLocalTimer();

      // startSession() creates the Firestore doc up front (status: 'active');
      // discarding must clean it up, or it lingers forever as a stale active
      // session in streak/insights queries. Fire-and-forget - don't block the
      // UI reset on it.
      if (sessionId != null) {
        ref.read(sessionRepositoryProvider).deleteSession(sessionId).catchError(
          (e) {
            debugPrint('❌ Error deleting discarded session: $e');
          },
        );
      }

      debugPrint('✅ Session discarded without saving');
    } catch (e) {
      debugPrint('❌ Error discarding session: $e');
      _isManuallyEnding = false;
    }
  }
}

// ============================================================================
// PROVIDERS
// ============================================================================

final focusSessionProvider =
    NotifierProvider<FocusSessionNotifier, FocusSessionState>(() {
      return FocusSessionNotifier();
    });

final isSessionActiveProvider = Provider<bool>((ref) {
  return ref.watch(focusSessionProvider.select((s) => s.isActive));
});

final sessionElapsedTimeProvider = Provider<String>((ref) {
  final elapsed = ref.watch(
    focusSessionProvider.select((s) => s.elapsedSeconds ?? 0),
  );
  final minutes = elapsed ~/ 60;
  final seconds = elapsed % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
});

final sessionRemainingTimeProvider = Provider<String>((ref) {
  final remaining = ref.watch(
    focusSessionProvider.select((s) => s.remainingSeconds ?? 0),
  );
  final minutes = remaining ~/ 60;
  final seconds = remaining % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
});
