library teashop_pos.presentation.admin.screens.admin_payment_methods_screen;

import 'package:flutter/material.dart';
import '../../app_theme.dart';

class _PaymentMethod {
  _PaymentMethod({
    required this.id,
    required this.name,
    required this.icon,
    required this.isActive,
  });
  final String id;
  final String name;
  final IconData icon;
  bool isActive;
}

/// Payment Methods management screen.
class AdminPaymentMethodsScreen extends StatefulWidget {
  const AdminPaymentMethodsScreen({super.key});

  @override
  State<AdminPaymentMethodsScreen> createState() =>
      _AdminPaymentMethodsScreenState();
}

class _AdminPaymentMethodsScreenState
    extends State<AdminPaymentMethodsScreen> {
  final List<_PaymentMethod> _methods = [
    _PaymentMethod(id: 'cash', name: 'ငွေသား', icon: Icons.payments, isActive: true),
    _PaymentMethod(id: 'kpay', name: 'KPay', icon: Icons.phone_android, isActive: true),
    _PaymentMethod(id: 'wavepay', name: 'Wave Pay', icon: Icons.waves, isActive: false),
    _PaymentMethod(id: 'cbpay', name: 'CB Pay', icon: Icons.credit_card, isActive: false),
    _PaymentMethod(id: 'aya', name: 'AYA Pay', icon: Icons.account_balance, isActive: false),
  ];

  Future<void> _addMethod() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ငွေပေးချေမှုနည်းလမ်းအသစ်'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'အမည်',
            hintText: 'ဥပမာ: AliPay',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('မလုပ်တော့ပါ')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.sidebarBg,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('ထည့်မည်')),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null && result.isNotEmpty) {
      setState(() {
        _methods.add(_PaymentMethod(
          id: result.toLowerCase().replaceAll(' ', '_'),
          name: result,
          icon: Icons.payment,
          isActive: true,
        ));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              const Text('ငွေပေးချေမှုနည်းလမ်းများ',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _addMethod,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.sidebarBg,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('ထည့်မည်'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _methods.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final m = _methods[i];
              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: CircleAvatar(
                    backgroundColor: m.isActive
                        ? AdminColors.sidebarBg.withOpacity(0.1)
                        : Colors.grey.shade100,
                    child: Icon(m.icon,
                        color: m.isActive
                            ? AdminColors.sidebarBg
                            : Colors.grey.shade400),
                  ),
                  title: Text(m.name,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: m.isActive
                              ? AppColors.onSurface
                              : Colors.grey.shade400)),
                  subtitle: Text(m.isActive ? 'အသုံးပြုနိုင်' : 'ပိတ်ထား',
                      style: TextStyle(
                          fontSize: 12,
                          color: m.isActive
                              ? AppColors.success
                              : Colors.grey.shade400)),
                  trailing: Switch(
                    value: m.isActive,
                    activeColor: AdminColors.sidebarBg,
                    onChanged: (v) => setState(() => m.isActive = v),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

