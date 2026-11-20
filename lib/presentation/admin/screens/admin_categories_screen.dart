library teashop_pos.presentation.admin.screens.admin_categories_screen;

import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../../data/database/app_database.dart';
import '../admin_menu_management.dart' show MenuManagementScreen;

/// Categories screen -- manage menu categories.
///
/// Features:
/// * Tap a category → pushes the Menu screen as a route, automatically
///   filtered to that category's items (via [MenuManagementScreen.initialCategory]).
/// * "+ ထည့်မည်" button → dialog with a Myanmar Unicode text input to add
///   a new category.
/// * Long-press a category → bottom sheet with Edit / Delete actions.
/// * Swipe a category row to the right → delete (with confirmation).
class AdminCategoriesScreen extends StatefulWidget {
  const AdminCategoriesScreen({super.key});

  @override
  State<AdminCategoriesScreen> createState() => _AdminCategoriesScreenState();
}

class _AdminCategoriesScreenState extends State<AdminCategoriesScreen> {
  final AppDatabase _db = AppDatabase.instance;
  List<String> _categories = [];
  Map<String, int> _itemCounts = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cats = await _db.getCategories();
      final counts = await _db.menuItemCountsByCategory();
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _itemCounts = counts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// Navigates to the Menu Items screen filtered by [category].
  ///
  /// The category *name* is passed to [MenuManagementScreen.initialCategory]
  /// (categories are uniquely identified by name in this schema). When the
  /// user pops back, the list is reloaded so item counts stay in sync with
  /// any edits/deletes made on the menu screen.
  Future<void> _openCategory(String category) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: AppColors.surfaceCream,
          appBar: AppBar(
            backgroundColor: AdminColors.sidebarBg,
            foregroundColor: Colors.white,
            title: Text(
              '📋 $category',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ),
          body: MenuManagementScreen(initialCategory: category),
        ),
      ),
    );
    if (mounted) _load();
  }

  // ── Add ──────────────────────────────────────────────────────────────────

  Future<void> _addCategory() async {
    final saved = await _showNameDialog(
      title: 'အမျိုးအစားအသစ်',
      initialName: '',
    );
    if (saved == null || saved.isEmpty) return;
    final id = await _db.insertCategory(saved);
    if (!mounted) return;
    if (id == 0) {
      _snack('"$saved" အမျိုးအစား ရှိပြီးသား ဖြစ်ပါသည်');
      return;
    }
    await _load();
    if (mounted) _snack('$saved အမျိုးအစားထည့်သွင်းပြီး');
  }

  // ── Edit (rename) ────────────────────────────────────────────────────────

  Future<void> _editCategory(String category) async {
    final saved = await _showNameDialog(
      title: 'အမျိုးအစား အမည်ပြောင်းမည်',
      initialName: category,
    );
    if (saved == null || saved.isEmpty || saved == category) return;
    await _db.renameCategory(category, saved);
    await _load();
    if (mounted) _snack('"$category" → "$saved" အမည်ပြောင်းပြီး');
  }

  // ── Delete ───────────────────────────────────────────────────────────────

  Future<bool> _confirmDelete(String category) async {
    final count = _itemCounts[category] ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('အမျိုးအစား ဖျက်မည်လား?'),
        content: Text(
          '"$category" အမျိုးအစားနှင့် ထဲရှိ ပစ္စည်း $count မျိုး အားလုံး '
          'ဖျက်သွားပါမည်။\nပြန်ပြင်၍မရပါ။',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('မဖျက်တော့ပါ'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ဖျက်မည်'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteCategory(String category) async {
    if (!await _confirmDelete(category)) return;
    await _db.deleteCategory(category);
    await _load();
    if (mounted) _snack('"$category" ဖျက်ပြီးပါပြီ');
  }

  // ── Long-press options sheet ─────────────────────────────────────────────

  Future<void> _showOptions(String category) async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                category,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit_outlined,
                  color: AdminColors.sidebarBg),
              title: const Text('အမည်ပြောင်းမည်'),
              onTap: () {
                Navigator.pop(ctx);
                _editCategory(category);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red.shade700),
              title: const Text('ဖျက်မည်'),
              onTap: () {
                Navigator.pop(ctx);
                _deleteCategory(category);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Shared name input dialog (add & edit) ────────────────────────────────

  Future<String?> _showNameDialog({
    required String title,
    required String initialName,
  }) async {
    final ctrl = TextEditingController(text: initialName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'အမျိုးအစားအမည်',
            hintText: 'ဥပမာ: ကော်ဖီ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('မလုပ်တော့ပါ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.sidebarBg,
              foregroundColor: Colors.white,
            ),
            child: const Text('သိမ်းမည်'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AdminColors.sidebarBg,
      ),
    );
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
                final count = _itemCounts[cat] ?? 0;
                return Dismissible(
                  key: ValueKey('category-$cat'),
                  direction: DismissDirection.startToEnd,
                  background: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 20),
                    decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.delete_outline,
                        color: Colors.white, size: 26),
                  ),
                  confirmDismiss: (_) async => _confirmDelete(cat),
                  onDismissed: (_) async {
                    await _db.deleteCategory(cat);
                    await _load();
                    if (mounted) _snack('"$cat" ဖျက်ပြီးပါပြီ');
                  },
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    child: ListTile(
                      onTap: () => _openCategory(cat),
                      onLongPress: () => _showOptions(cat),
                      leading: CircleAvatar(
                        backgroundColor:
                            AdminColors.sidebarBg.withValues(alpha: 0.1),
                        child: Text(
                          cat.isNotEmpty ? cat[0].toUpperCase() : '?',
                          style: const TextStyle(
                              color: AdminColors.sidebarBg,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(cat,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('ပစ္စည်း $count မျိုး',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      trailing: const Icon(Icons.chevron_right,
                          color: AdminColors.sidebarBg),
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

