library teashop_pos.presentation.admin.screens.admin_income_expense_screen;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app_theme.dart';
import '../../../data/database/app_database.dart';

class _Transaction {
  _Transaction({
    required this.id,
    required this.type, // 'income' | 'expense'
    required this.title,
    required this.amount,
    required this.date,
    this.note = '',
  });
  final int id;
  final String type;
  final String title;
  final double amount;
  final DateTime date;
  final String note;
}

/// Income / Expense combined ledger screen.
class AdminIncomeExpenseScreen extends StatefulWidget {
  const AdminIncomeExpenseScreen({super.key});

  @override
  State<AdminIncomeExpenseScreen> createState() =>
      _AdminIncomeExpenseScreenState();
}

class _AdminIncomeExpenseScreenState extends State<AdminIncomeExpenseScreen> {
  final AppDatabase _db = AppDatabase.instance;
  final DateFormat _fmt = DateFormat('dd MMM, HH:mm');
  int _nextId = 1;
  final List<_Transaction> _txns = [];
  double _salesRevenue = 0;
  bool _loading = false;

  double get _totalIncome =>
      _salesRevenue + _txns.where((t) => t.type == 'income').fold(0.0, (s, t) => s + t.amount);
  double get _totalExpense =>
      _txns.where((t) => t.type == 'expense').fold(0.0, (s, t) => s + t.amount);
  double get _netProfit => _totalIncome - _totalExpense;

  @override
  void initState() {
    super.initState();
    _loadRevenue();
  }

  Future<void> _loadRevenue() async {
    setState(() => _loading = true);
    try {
      final stats = await _db.getOrderStats();
      if (!mounted) return;
      setState(() {
        _salesRevenue = stats.todayRevenue;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _addTransaction(String type) async {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String? error;
    final isIncome = type == 'income';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(isIncome ? 'ဝင်ငွေ ထည့်မည်' : 'ထွက်ငွေ ထည့်မည်'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'ခေါင်းစဉ်'),
                  autofocus: true,
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
                  decoration: const InputDecoration(
                      labelText: 'မှတ်စု (ရွေးချယ်မနတ်)'),
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
                backgroundColor: isIncome ? AppColors.success : AppColors.error,
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
        _txns.insert(
          0,
          _Transaction(
            id: _nextId++,
            type: type,
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
              const Text('ဝင်ငွေ / ထွက်ငွေ',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _addTransaction('income'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                icon: const Icon(Icons.arrow_downward, size: 16),
                label: const Text('ဝင်', style: TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                onPressed: () => _addTransaction('expense'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                icon: const Icon(Icons.arrow_upward, size: 16),
                label: const Text('ထွက်', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
        // Summary row
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: _summaryCard('ဝင်ငွေ', _totalIncome, AppColors.success,
                    Icons.arrow_downward),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _summaryCard('ထွက်ငွေ', _totalExpense, AppColors.error,
                    Icons.arrow_upward),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _summaryCard(
                    'အသားတင်',
                    _netProfit,
                    _netProfit >= 0 ? AdminColors.sidebarBg : AppColors.error,
                    Icons.account_balance_wallet),
              ),
            ],
          ),
        ),
        // Sales revenue note
        if (_salesRevenue > 0)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.success.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.point_of_sale,
                    color: AppColors.success, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ရောင်းဝင်ငွေ: ${formatMoney(_salesRevenue)} (auto)',
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.success,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        // Transaction list
        Expanded(
          child: _txns.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.account_balance_wallet,
                          size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('မှတ်တမ်း မရှိသေးပါ',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: _txns.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _txnTile(_txns[i]),
                ),
        ),
      ],
    );
  }

  Widget _summaryCard(
      String label, double amount, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            'K ${amount.toStringAsFixed(0)}',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(label,
              style:
                  const TextStyle(fontSize: 11, color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _txnTile(_Transaction txn) {
    final isIncome = txn.type == 'income';
    final color = isIncome ? AppColors.success : AppColors.error;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(
            isIncome ? Icons.arrow_downward : Icons.arrow_upward,
            color: color,
            size: 20,
          ),
        ),
        title: Text(txn.title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${_fmt.format(txn.date)}${txn.note.isNotEmpty ? '  •  ${txn.note}' : ''}',
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        trailing: Text(
          '${isIncome ? '+' : '-'}K ${txn.amount.toStringAsFixed(0)}',
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 15),
        ),
      ),
    );
  }
}

