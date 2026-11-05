library teashop_pos.presentation.admin.screens.admin_expenses_screen;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app_theme.dart';

class _Expense {
  _Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.date,
    required this.note,
  });
  final int id;
  final String title;
  final double amount;
  final DateTime date;
  final String note;
}

/// Expenses screen – log and view business expenses.
class AdminExpensesScreen extends StatefulWidget {
  const AdminExpensesScreen({super.key});

  @override
  State<AdminExpensesScreen> createState() => _AdminExpensesScreenState();
}

class _AdminExpensesScreenState extends State<AdminExpensesScreen> {
  final DateFormat _fmt = DateFormat('dd MMM, HH:mm');
  int _nextId = 1;
  final List<_Expense> _expenses = [];
  double get _total => _expenses.fold(0, (s, e) => s + e.amount);

  Future<void> _addExpense() async {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('ထွက်ငွေမှတ်တမ်း'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'ခေါင်းစဉ်'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'ပမာဏ (ကျပ်)', prefixText: 'K '),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  decoration:
                      const InputDecoration(labelText: 'မှတ်စု (ရွေးချယ်မနတ်)'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style:
                          const TextStyle(color: AppColors.error, fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('မလုပ်တော့ပါ')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.sidebarBg,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (titleCtrl.text.trim().isEmpty) {
                  setS(() => error = 'ခေါင်းစဉ် ထည့်ပါ');
                  return;
                }
                final amt = double.tryParse(amountCtrl.text);
                if (amt == null || amt <= 0) {
                  setS(() => error = 'ပမာဏ မှန်မှန်ကန်ကန် ထည့်ပါ');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('မှတ်တမ်းတင်မည်'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      final amt = double.tryParse(amountCtrl.text) ?? 0;
      setState(() {
        _expenses.insert(
          0,
          _Expense(
            id: _nextId++,
            title: titleCtrl.text.trim(),
            amount: amt,
            date: DateTime.now(),
            note: noteCtrl.text.trim(),
          ),
        );
      });
    }
    titleCtrl.dispose();
    amountCtrl.dispose();
    noteCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              const Text('ထွက်ငွေ',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _addExpense,
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
        // Summary card
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AdminColors.sidebarBg,
                AdminColors.sidebarBg.withOpacity(0.8)
              ],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.trending_down, color: Colors.white, size: 32),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ယနေ့ ထွက်ငွေ စုစုပေါင်း',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Text(
                    'K ${_total.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_expenses.isEmpty)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('ထွက်ငွေ မှတ်တမ်း မရှိသေးပါ',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _expenses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final e = _expenses[i];
                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: CircleAvatar(
                      backgroundColor: AppColors.error.withOpacity(0.1),
                      child: const Icon(Icons.arrow_upward,
                          color: AppColors.error, size: 20),
                    ),
                    title: Text(e.title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${_fmt.format(e.date)}${e.note.isNotEmpty ? '  •  ${e.note}' : ''}',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                    trailing: Text(
                      'K ${e.amount.toStringAsFixed(0)}',
                      style: const TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
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

