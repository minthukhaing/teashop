// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:teashop_pos/main.dart';
import 'package:teashop_pos/core/auth/password_hasher.dart';
import 'package:teashop_pos/core/auth/waiter_permissions.dart';
import 'package:teashop_pos/core/auth/waiter_auth.dart';

void main() {
  testWidgets('App boots to the role selection screen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const TeashopApp());

    // The default launch (no APP_MODE flag) shows the role picker.
    expect(find.text('Teashop POS'), findsOneWidget);
    expect(find.text('Admin Host'), findsOneWidget);
    expect(find.text('Waiter'), findsOneWidget);
    expect(find.text('Kitchen Display'), findsOneWidget);
  });

  testWidgets('Tapping Waiter opens the waiter login screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const TeashopApp());
    await tester.tap(find.text('Waiter'));
    await tester.pumpAndSettle();
    expect(find.text('Waiter Login'), findsOneWidget);
  });

  group('WaiterPermissions', () {
    test('encode/decode round-trips', () {
      final perms = [
        WaiterPermissions.takeOrders,
        WaiterPermissions.cancelOrders,
      ];
      expect(WaiterPermissions.decode(WaiterPermissions.encode(perms)), perms);
    });

    test('decode handles malformed input gracefully', () {
      expect(WaiterPermissions.decode(null), isEmpty);
      expect(WaiterPermissions.decode(''), isEmpty);
      expect(WaiterPermissions.decode('not json'), isEmpty);
    });

    test('default permissions include take and view but not cancel', () {
      expect(WaiterPermissions.defaultPermissions,
          contains(WaiterPermissions.takeOrders));
      expect(WaiterPermissions.defaultPermissions,
          contains(WaiterPermissions.viewOrders));
      expect(WaiterPermissions.defaultPermissions,
          isNot(contains(WaiterPermissions.cancelOrders)));
    });
  });

  group('PasswordHasher', () {
    test('hash is deterministic', () {
      expect(PasswordHasher.hash('waiter123'),
          PasswordHasher.hash('waiter123'));
    });

    test('different passwords produce different hashes', () {
      expect(PasswordHasher.hash('waiter123'),
          isNot(PasswordHasher.hash('admin123')));
    });

    test('verify matches the original password', () {
      final hash = PasswordHasher.hash('secret');
      expect(PasswordHasher.verify('secret', hash), isTrue);
      expect(PasswordHasher.verify('wrong', hash), isFalse);
    });
  });

  group('WaiterAuth', () {
    test('starts logged out and gates by permission', () {
      final auth = WaiterAuth.instance;
      auth.logout();
      expect(auth.isLoggedIn, isFalse);
      expect(auth.can(WaiterPermissions.takeOrders), isFalse);

      auth.startSession(
        username: 'alice',
        displayName: 'Alice',
        permissions: [
          WaiterPermissions.takeOrders,
          WaiterPermissions.viewOrders,
        ],
      );
      expect(auth.isLoggedIn, isTrue);
      expect(auth.can(WaiterPermissions.takeOrders), isTrue);
      expect(auth.can(WaiterPermissions.cancelOrders), isFalse);
      expect(auth.displayNameOrUsername, 'Alice');

      auth.logout();
      expect(auth.isLoggedIn, isFalse);
    });
  });
}
