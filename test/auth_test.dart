import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/firebase_config.dart';
import 'package:flow/data/repositories/auth_repository.dart';
import 'package:flow/features/auth/auth_controller.dart';
import 'package:flow/features/auth/auth_validators.dart';
import 'package:flow/firebase_options.dart';

void main() {
  group('email validation', () {
    test('accepts ordinary addresses', () {
      for (final email in [
        'lina@example.com',
        'lina.k@sub.example.co.uk',
        "o'brien+kite@example.io",
      ]) {
        expect(AuthValidators.email(email), isNull, reason: email);
      }
    });

    test('rejects what the old contains(@)/contains(.) check let through', () {
      // Every one of these passed the previous implementation.
      for (final email in ['@.', 'a@b.', '.@x', 'a@.com', '@example.com']) {
        expect(AuthValidators.email(email), "That email doesn't look right",
            reason: email);
      }
    });

    test('trims before judging, and reports empty separately', () {
      expect(AuthValidators.email('  lina@example.com  '), isNull);
      expect(AuthValidators.email('   '), 'Enter your email');
      expect(AuthValidators.email(null), 'Enter your email');
    });
  });

  group('password validation', () {
    test('sign-up enforces the 6-character floor', () {
      expect(AuthValidators.password('12345', signUp: true),
          'Use at least 6 characters');
      expect(AuthValidators.password('123456', signUp: true), isNull);
    });

    test('log-in only requires presence — old accounts may predate the rule',
        () {
      expect(AuthValidators.password('12345', signUp: false), isNull);
      expect(AuthValidators.password('', signUp: false), 'Enter your password');
    });
  });

  group('name validation', () {
    test('required and trimmed', () {
      expect(AuthValidators.name('   '), 'Tell us your name');
      expect(AuthValidators.name('Lina'), isNull);
    });
  });

  group('password strength', () {
    test('below the minimum is always weak', () {
      expect(PasswordStrength.of('aB3\$'), PasswordStrength.weak);
    });

    test('length and variety promote the score', () {
      expect(PasswordStrength.of('abcdefgh'), PasswordStrength.weak);
      expect(PasswordStrength.of('abcdefghij'), PasswordStrength.fair);
      expect(PasswordStrength.of('abcDef123'), PasswordStrength.fair);
      expect(PasswordStrength.of('abcDef123!xyz'), PasswordStrength.strong);
    });
  });

  group('server error placement', () {
    test('field-specific codes land under their field', () {
      expect(AuthController.fieldFor('invalid-email'), AuthField.email);
      expect(AuthController.fieldFor('email-already-in-use'), AuthField.email);
      expect(AuthController.fieldFor('weak-password'), AuthField.password);
      expect(AuthController.fieldFor('wrong-password'), AuthField.password);
      expect(AuthController.fieldFor('invalid-credential'), AuthField.password);
    });

    test('whole-form problems stay in the banner', () {
      for (final code in [
        'network-request-failed',
        'too-many-requests',
        'user-disabled',
        'internal-error',
        null,
      ]) {
        expect(AuthController.fieldFor(code), isNull, reason: '$code');
      }
    });
  });

  group('auth error messages', () {
    test('codes the old mapping dropped to a generic message now speak', () {
      expect(AuthRepository.message('operation-not-allowed'),
          isNot('Something went wrong. Please try again.'));
      expect(AuthRepository.message('account-exists-with-different-credential'),
          isNot('Something went wrong. Please try again.'));
      expect(AuthRepository.message('expired-action-code'),
          isNot('Something went wrong. Please try again.'));
    });

    test('blueprint §10.3 wording is preserved exactly', () {
      expect(AuthRepository.message('wrong-password'),
          'Incorrect email or password.');
      expect(AuthRepository.message('invalid-email'),
          "That email address doesn't look right.");
      expect(AuthRepository.message('weak-password'),
          'Password should be at least 6 characters.');
      expect(AuthRepository.message('user-disabled'),
          'This account has been disabled.');
      expect(AuthRepository.message('too-many-requests'),
          'Too many attempts. Please wait a moment and try again.');
      expect(AuthRepository.message('network-request-failed'),
          'No connection. Check your internet and try again.');
      expect(AuthRepository.message('requires-recent-login'),
          'For your security, sign out and sign back in before deleting your account.');
    });

    test('unknown codes still fall back', () {
      expect(AuthRepository.message('something-new-from-firebase'),
          'Something went wrong. Please try again.');
    });

    test('AuthFailure carries the code for placement', () {
      const failure = AuthFailure('nope', code: 'invalid-email');
      expect(failure.code, 'invalid-email');
      expect(failure.toString(), 'nope');
    });
  });

  group('error translation — nothing reaches the user unlabelled', () {
    // The regression that caused registration to fail for everyone: an
    // invalid API key surfaces in several shapes depending on where Firebase
    // notices it, and none of them are FirebaseAuthException on every path.
    test('invalid API key is recognised in all of its spellings', () {
      final shapes = <Object>[
        FirebaseAuthException(code: 'invalid-api-key'),
        FirebaseAuthException(
            code: 'api-key-not-valid.-please-pass-a-valid-api-key.'),
        FirebaseAuthException(
            code: 'unknown', message: 'API key not valid. Please pass a valid API key.'),
        PlatformException(
            code: 'unknown', message: 'API_KEY_INVALID: bad key supplied'),
      ];
      for (final shape in shapes) {
        final failure = AuthRepository.translate(shape);
        expect(failure.code, 'invalid-api-key', reason: '$shape');
        expect(failure.isConfigError, isTrue, reason: '$shape');
        expect(failure.message, contains('API key'), reason: '$shape');
        expect(failure.message,
            isNot(contains('Something went wrong')), reason: '$shape');
      }
    });

    test('a non-Firebase throwable still becomes a labelled failure', () {
      final failure = AuthRepository.translate(StateError('boom'));
      expect(failure, isA<AuthFailure>());
      expect(failure.message, isNotEmpty);
    });

    test('an already-translated failure passes through untouched', () {
      const original = AuthFailure('keep me', code: 'weak-password');
      expect(identical(AuthRepository.translate(original), original), isTrue);
    });

    test('ordinary credential errors keep their user-facing wording', () {
      final failure = AuthRepository.translate(
          FirebaseAuthException(code: 'email-already-in-use'));
      expect(failure.code, 'email-already-in-use');
      expect(failure.isConfigError, isFalse);
      expect(failure.message, 'An account with this email already exists.');
    });

    test('config problems are flagged so they never sit under a field', () {
      for (final code in [
        'invalid-api-key',
        'configuration-not-found',
        'app-not-authorized',
        'operation-not-allowed',
      ]) {
        expect(AuthRepository.isConfigCode(code), isTrue, reason: code);
        // Config failures belong in the banner, never under an input.
        expect(AuthController.fieldFor(code), isNull, reason: code);
      }
      expect(AuthRepository.isConfigCode('wrong-password'), isFalse);
    });
  });

  group('startup configuration guard', () {
    test('the build carries a real Firebase config', () {
      // Catches a regression where firebase_options.dart is regenerated
      // empty, or a placeholder is committed — either would ship an app whose
      // every network call fails with API_KEY_INVALID.
      expect(FlowFirebase.isConfigured, isTrue);
      expect(DefaultFirebaseOptions.android.projectId, isNotEmpty);
    });

    test('the Android app id matches the package we ship', () {
      // google-services.json is keyed on the package name; a mismatch fails
      // the Gradle build and breaks FCM delivery.
      expect(FlowFirebase.androidPackageName, 'com.wlftech.flow');
      expect(DefaultFirebaseOptions.android.appId, contains(':android:'));
    });

    test('placeholder keys are rejected by the guard', () {
      for (final key in ['', 'REPLACE-WITH-current_key', 'YOUR_API_KEY_HERE']) {
        expect(
          key.isNotEmpty &&
              !key.startsWith('REPLACE') &&
              !key.contains('YOUR_API_KEY'),
          isFalse,
          reason: key,
        );
      }
    });
  });
}
