library teashop_pos.presentation.admin.screens.admin_categories_screen;

import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/models/menu_item.dart';

/// Categories screen – manage menu categories.
class AdminCategoriesScreen extends StatefulWidget {
  const AdminCategoriesScreen({super.key});

  @override
  State<AdminCategoriesScreen> createState() => _AdminCategoriesScreenState();
}

class _AdminCategoriesScreenState extends State<AdminCategoriesScreen> {
  final AppDatabase _db = AppDatabase.instance;
  List<String> _categories = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await _db.getMenuItems();
      if (!mounted) return;
      final cats = items.map((e) => e.category).toSet().toList()..sort();
      setState(() {
        _categories = cats;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _addCategory() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('အမျိုးအစားအသစ်'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'အမျိုးအစားအမည်',
            hintText: 'ဥပမာ: ကော်ဖီ',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('မလုပ်တော့ပါ')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.sidebarBg,
                foregroundColor: Colors.white,
              ),
              child: const Text('ထည့်မည်')),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null && result.isNotEmpty) {
      // Insert a placeholder item with this category so it shows up
      await _db.insertMenuItem(MenuItem(
        name: 'New Item',
        category: result,
        description: '',
        price: 0,
        available: false,
      ));
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$result အမျိုးအစားထည့်သွင်းပြီး'),
            backgroundColor: AdminColors.sidebarBg,
          ),
        );
      }
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
              const Text('အမျိုးအစားများ',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _addCategory,
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
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_categories.isEmpty)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('အမျိုးအစားများ မရှိသေးပါ',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final cat = _categories[i];
                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AdminColors.sidebarBg.withOpacity(0.1),
                      child: Text(
                        cat.isNotEmpty ? cat[0].toUpperCase() : '?',
                        style: const TextStyle(
                            color: AdminColors.sidebarBg,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(cat,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.chevron_right,
                        color: AdminColors.sidebarBg),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

