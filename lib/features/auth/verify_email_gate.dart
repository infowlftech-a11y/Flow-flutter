import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/sheets.dart';
import '../../providers/providers.dart';

/// The email-verification gate on the pay step (P6).
///
/// Returns true when booking may proceed. An unverified account gets the
/// sheet instead: a verification email is sent on open, and the sheet
/// resolves true only once a re-fetched account reports the tick. Money
/// never moves for an inbox nobody has proven.
///
/// This is a client-side gate by design — firestore.rules cannot demand
/// `email_verified` on the token without breaking every pinned emulator
/// test, whose auth contexts carry no such claim. Server-side enforcement
/// belongs to the App Check / Functions layer (FLOW_REDESIGN.md P6).
Future<bool> ensureEmailVerified(BuildContext context, WidgetRef ref) async {
  final auth = ref.read(authRepositoryProvider);
  if (auth.emailVerified) return true;

  final email = auth.currentUser?.email ?? 'your email address';

  // Send before asking — "check your inbox" must be true by the time it is
  // read. Failures surface in the sheet's resend button, so a failed first
  // send is recoverable without closing anything.
  try {
    await auth.sendEmailVerification();
  } catch (_) {}

  if (!context.mounted) return false;

  final verified = await showFlowSheet<bool>(
    context,
    title: 'Verify your email first',
    builder: (sheetContext) {
      var checking = false;
      var resending = false;
      return StatefulBuilder(
        builder: (sheetContext, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Symbols.mark_email_unread_rounded,
                    size: 22,
                    color: sheetContext.tones.azureBrand,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'We sent a link to $email',
                      style: inter(
                        14.5,
                        620,
                        color: sheetContext.scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Booking moves real money, so every account proves its '
                'inbox once. Tap the link in the email, then come back '
                'here — this screen stays where it is.',
                style: inter(
                  13,
                  480,
                  color: sheetContext.scheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              PrimaryButton(
                label: "I've tapped the link",
                busy: checking,
                onPressed: () async {
                  setSheet(() => checking = true);
                  try {
                    final ok = await ref
                        .read(authRepositoryProvider)
                        .reloadEmailVerified();
                    if (!sheetContext.mounted) return;
                    if (ok) {
                      Navigator.pop(sheetContext, true);
                    } else {
                      setSheet(() => checking = false);
                      showFlowToast(
                        sheetContext,
                        'Not verified yet — the link in the email is '
                        'what flips it.',
                      );
                    }
                  } catch (_) {
                    if (sheetContext.mounted) {
                      setSheet(() => checking = false);
                      showFlowToast(
                        sheetContext,
                        "Couldn't check just now. Try again.",
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: resending
                      ? null
                      : () async {
                          setSheet(() => resending = true);
                          try {
                            await ref
                                .read(authRepositoryProvider)
                                .sendEmailVerification();
                            if (sheetContext.mounted) {
                              showFlowToast(sheetContext, 'Email re-sent');
                            }
                          } catch (_) {
                            if (sheetContext.mounted) {
                              showFlowToast(
                                sheetContext,
                                "Couldn't resend. Try again in a minute.",
                              );
                            }
                          } finally {
                            if (sheetContext.mounted) {
                              setSheet(() => resending = false);
                            }
                          }
                        },
                  child: const Text('Resend the email'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  return verified ?? false;
}
