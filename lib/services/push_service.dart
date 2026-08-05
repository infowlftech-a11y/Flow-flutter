import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';

/// Registered before `runApp` so pushes arriving while the app is killed are
/// handled. Intentionally empty — the Cloud Function sends a `notification`
/// payload that Android renders itself; this exists so the plugin is
/// registered and tap-through data survives (§11.3).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Owns permission, the FCM token lifecycle, foreground snackbars and tap
/// routing (§11.3).
class PushController {
  PushController(this._ref);
  final Ref _ref;

  final _messaging = FirebaseMessaging.instance;
  final List<StreamSubscription> _subs = [];
  String? _tokenSyncedForUid;

  /// The shell's navigator context supplier — set by the app root.
  ///
  /// Nullable on purpose: the navigator has no context before the first frame
  /// or while it is being rebuilt, and a push can land in either window. The
  /// callers below already guard for null — returning it (rather than
  /// asserting) is what lets that guard actually run.
  BuildContext? Function()? contextSupplier;

  void start() {
    // Foreground pushes → in-app snackbar with VIEW (Android suppresses the
    // system notification while focused).
    _subs.add(FirebaseMessaging.onMessage.listen(_onForeground));
    // Tap from background.
    _subs.add(FirebaseMessaging.onMessageOpenedApp.listen(handleTap));
    // Token refresh.
    _subs.add(_messaging.onTokenRefresh.listen((token) {
      final uid = _ref.read(currentUidProvider);
      if (uid != null) {
        _ref.read(userRepositoryProvider).saveFcmToken(uid, token).ignore();
      }
    }));
    // Cold start via a notification tap.
    _messaging.getInitialMessage().then((m) {
      if (m != null) handleTap(m);
    });
  }

  /// Requests permission (required on Android 13+) the first time a uid
  /// appears, then writes the token. A failure (e.g. mid-onboarding, no
  /// profile document yet) is swallowed and retried next launch.
  Future<void> syncTokenFor(String uid) async {
    if (_tokenSyncedForUid == uid) return;
    _tokenSyncedForUid = uid;
    try {
      await _messaging.requestPermission();
      final token = await _messaging.getToken();
      if (token != null) {
        await _ref.read(userRepositoryProvider).saveFcmToken(uid, token);
      }
    } catch (_) {
      _tokenSyncedForUid = null; // retry next launch / next uid emission
    }
  }

  void _onForeground(RemoteMessage message) {
    final context = contextSupplier?.call();
    if (context == null || !context.mounted) return;
    final title = message.notification?.title ?? 'FLOW';
    final body = message.notification?.body ?? '';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      duration: const Duration(seconds: 5),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (body.isNotEmpty) Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
      action: SnackBarAction(
        label: 'VIEW',
        onPressed: () => handleTap(message),
      ),
    ));
  }

  /// Tap routing (§11.3). v2.6 routed riders to a bare `/sessions`; the push
  /// carries `bookingId` in its data payload, so we close that gap and land
  /// on the specific booking — same deep link as the in-app list.
  void handleTap(RemoteMessage message) {
    final context = contextSupplier?.call();
    if (context == null || !context.mounted) return;
    final type = (message.data['type'] ?? '').toString();
    final bookingId = (message.data['bookingId'] ?? '').toString();
    final isTrainer = _ref.read(sessionProvider).isTrainer;

    if (type.startsWith('booking') || bookingId.isNotEmpty) {
      if (isTrainer) {
        context.go('/home');
      } else {
        context.go(bookingId.isNotEmpty
            ? '/sessions?highlight=$bookingId'
            : '/sessions');
      }
    } else if (type == 'message') {
      context.go('/inbox');
    } else {
      context.push('/notifications');
    }
  }

  /// Forget which uid this device's token was written for.
  ///
  /// Called on sign-out. Without it the latch in [syncTokenFor] still holds
  /// the departed uid, so signing back in as that same user inside one app
  /// session short-circuits and never rewrites the token that sign-out just
  /// deleted — leaving them with no pushes until the next cold start.
  void forgetSyncedUid() => _tokenSyncedForUid = null;

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }
}

final pushControllerProvider = Provider<PushController>((ref) {
  final controller = PushController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});
