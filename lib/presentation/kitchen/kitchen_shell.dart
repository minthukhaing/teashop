library teashop_pos.presentation.kitchen.kitchen_shell;

import 'package:flutter/material.dart';

import 'kitchen_display.dart';

/// Kitchen Display shell: shows live order tickets polled from the Admin Host.
class KitchenShell extends StatelessWidget {
  const KitchenShell({super.key});

  @override
  Widget build(BuildContext context) => const KitchenDisplayScreen();
}
