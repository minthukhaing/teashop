import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'presentation/app_mode.dart';
import 'presentation/app_theme.dart';
import 'presentation/role_selection_screen.dart';
import 'presentation/admin/admin_login_screen.dart';
import 'presentation/waiter/waiter_login_screen.dart';
import 'presentation/kitchen/kitchen_shell.dart';

void main() {
  _initSqfliteFfi();
  runApp(const TeashopApp());
}

/// Initializes the FFI SQLite factory on desktop platforms (Windows, macOS,
/// Linux) where the `sqflite` plugin has no native backend.
///
/// On Android/iOS the native `sqflite` plugin is used instead, and web is not
/// supported by this app, so this is a no-op there.
void _initSqfliteFfi() {
  if (kIsWeb) return;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

class TeashopApp extends StatelessWidget {
  const TeashopApp({super.key});

  @override
  Widget build(BuildContext context) {
    final rawMode = const String.fromEnvironment('APP_MODE', defaultValue: '');
    final adminIp = const String.fromEnvironment('APP_ADMIN_IP', defaultValue: '');
    if (adminIp.isNotEmpty) {
      AppConfig.instance.adminIp = adminIp;
    }

    final mode = currentAppMode();
    final home = rawMode.isNotEmpty
        ? _homeForMode(mode)
        : const RoleSelectionScreen();

    return MaterialApp(
      title: 'Teashop POS',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      home: home,
    );
  }
}

Widget _homeForMode(AppMode mode) {
  switch (mode) {
    case AppMode.admin:
      return const AdminLoginScreen();
    case AppMode.waiter:
      return const WaiterLoginScreen();
    case AppMode.kitchen:
      return const KitchenShell();
  }
}