library teashop_pos.presentation.admin.admin_staff_management;

import 'package:flutter/material.dart';

import '../../../core/auth/waiter_permissions.dart';
import '../../../data/database/app_database.dart';
import '../../../data/models/user_account.dart';
import '../app_theme.dart';
import '../common_widgets.dart';
import '../responsive_helpers.dart';

/// Admin screen for managing waiter accounts: create/edit/delete waiters,
/// reset passwords, toggle active state and grant per-waiter permissions.
class AdminStaffManagementScreen extends StatefulWidget {
  const AdminStaffManagementScreen({super.key});

  @override
  State<AdminStaffManagementScreen> createState() =>
      _AdminStaffManagementScreenState();
}

class _AdminStaffManagementScreenState
    extends State<AdminStaffManagementScreen> {
  final AppDatabase _db = AppDatabase.instance;
  List<UserAccount> _staff = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final users = await _db.getUsers(role: 'waiter');
      if (!mounted) return;
      setState(() {
        _staff = users;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleActive(UserAccount user) async {
    await _db.toggleUserActive(user.id!, !user.active);
    await _load();
  }

  Future<void> _delete(UserAccount user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove waiter?'),
        content: Text('Delete the staff account "${user.username}"? '
            'They will no longer be able to log in.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _db.deleteUser(user.id!);
      await _load();
    }
  }

  Future<void> _editOrAdd([UserAccount? existing]) async {
    final isEdit = existing != null;
    final userCtrl = TextEditingController(text: existing?.username ?? '');
    final nameCtrl = TextEditingController(text: existing?.displayName ?? '');
    final passCtrl = TextEditingController();
    final perms = <String>{
      ...(existing?.permissions ?? WaiterPermissions.defaultPermissions),
    };
    bool active = existing?.active ?? true;
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(isEdit ? 'Edit Waiter' : 'New Waiter',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  appTextField(
                    context: context,
                    label: 'Username',
                    controller: userCtrl,
                    prefixIcon: Icons.person,
                  ),
                  const SizedBox(height: 12),
                  appTextField(
                    context: context,
                    label: 'Display name (optional)',
                    controller: nameCtrl,
                  ),
                  if (!isEdit) ...[
                    const SizedBox(height: 12),
                    appTextField(
                      context: context,
                      label: 'Password',
                      controller: passCtrl,
                      prefixIcon: Icons.lock,
                      obscureText: true,
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text('Permissions',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  for (final key in WaiterPermissions.all)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: perms.contains(key),
                      title: Text(WaiterPermissions.label(key)),
                      subtitle: Text(WaiterPermissions.description(key),
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.muted)),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          perms.add(key);
                        } else {
                          perms.remove(key);
                        }
                      }),
                    ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: active,
                    title: const Text('Active'),
                    onChanged: (v) => setState(() => active = v),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!,
                        style: const TextStyle(
                            color: AppColors.error, fontSize: 13)),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          final username = userCtrl.text.trim();
                          if (username.isEmpty) {
                            setState(() => error = 'Username is required');
                            return;
                          }
                          try {
                            if (isEdit) {
                              await _db.updateUser(existing.copyWith(
                                displayName: nameCtrl.text.trim().isEmpty
                                    ? null
                                    : nameCtrl.text.trim(),
                                permissions: perms.toList(),
                                active: active,
                              ));
                            } else {
                              if (passCtrl.text.length < 4) {
                                setState(() => error =
                                    'Password must be at least 4 characters');
                                return;
                              }
                              await _db.insertUser(
                                username: username,
                                password: passCtrl.text,
                                role: 'waiter',
                                displayName: nameCtrl.text.trim().isEmpty
                                    ? null
                                    : nameCtrl.text.trim(),
                                permissions: perms.toList(),
                              );
                            }
                            if (!context.mounted) return;
                            Navigator.pop(context, true);
                          } catch (e) {
                            setState(() => error = 'Could not save: $e');
                          }
                        },
                        child: Text(isEdit ? 'Save' : 'Create'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _resetPassword(UserAccount user) async {
    final passCtrl = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Reset password',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Set a new password for "${user.username}".',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.muted)),
                  const SizedBox(height: 16),
                  appTextField(
                    context: context,
                    label: 'New password',
                    controller: passCtrl,
                    prefixIcon: Icons.lock,
                    obscureText: true,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!,
                        style: const TextStyle(
                            color: AppColors.error, fontSize: 13)),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          if (passCtrl.text.length < 4) {
                            setState(() => error =
                                'Password must be at least 4 characters');
                            return;
                          }
                          try {
                            await _db.updateUserPassword(
                                user.id!, passCtrl.text);
                            if (!context.mounted) return;
                            Navigator.pop(context, true);
                          } catch (e) {
                            setState(() => error = 'Could not update: $e');
                          }
                        },
                        child: const Text('Update'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (ok == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password updated for ${user.username}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text('Staff Accounts',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: appButton(
                      label: '+ Add Waiter',
                      onPressed: () => _editOrAdd()),
                ),
              ],
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_staff.isEmpty)
            const Expanded(
                child: Center(
                    child: Text(
                        'No waiter accounts yet. Add one to get started.')))
          else
            Expanded(
              child: ResponsiveGrid(
                compact: 1,
                medium: 2,
                expanded: 3,
                large: 4,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                childAspectRatio: 1.1,
                itemCount: _staff.length,
                itemBuilder: (context, index) => _waiterCard(_staff[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _waiterCard(UserAccount user) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.accent.withOpacity(0.15),
                  child: Text(user.username.isNotEmpty
                      ? user.username[0].toUpperCase()
                      : '?'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.username,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(user.displayName ?? 'No display name',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Switch(
                    value: user.active, onChanged: (_) => _toggleActive(user)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final key in WaiterPermissions.all)
                  Chip(
                    label: Text(WaiterPermissions.label(key)),
                    backgroundColor: user.permissions.contains(key)
                        ? AppColors.success.withOpacity(0.15)
                        : Colors.grey.shade200,
                    labelStyle: TextStyle(
                        fontSize: 11,
                        color: user.permissions.contains(key)
                            ? AppColors.success
                            : AppColors.muted),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 2),
                  ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.vpn_key, color: AppColors.primary),
                  tooltip: 'Reset password',
                  onPressed: () => _resetPassword(user),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: AppColors.primary),
                  onPressed: () => _editOrAdd(user),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.error),
                  onPressed: () => _delete(user),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
